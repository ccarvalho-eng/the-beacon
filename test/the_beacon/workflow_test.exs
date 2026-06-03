defmodule TheBeacon.WorkflowTest do
  use ExUnit.Case, async: false

  alias TheBeacon.Workflows.SecurityCheck

  defmodule FakeRuntime do
    def deliver_payload(payload) do
      send(:persistent_term.get({__MODULE__, :owner}), {:payload_delivered, payload})
      :ok
    end

    def drain_once do
      send(:persistent_term.get({__MODULE__, :owner}), :drained_once)
      {:ok, :none}
    end
  end

  defmodule FakeJobQueue do
    def enqueue(queue_id, topic, payload, opts) do
      send(
        :persistent_term.get({__MODULE__, :owner}),
        {:enqueued, queue_id, topic, payload, opts}
      )

      {:ok,
       %{
         id: Keyword.get(opts, :id, "job-id"),
         vesting_time:
           opts
           |> Keyword.get(:at, DateTime.utc_now())
           |> DateTime.to_unix(:millisecond)
       }}
    end
  end

  setup do
    :persistent_term.put({FakeRuntime, :owner}, self())
    :persistent_term.put({FakeJobQueue, :owner}, self())
    :ok
  end

  test "security workflow exposes manual and scheduled security check triggers" do
    assert {:ok, spec} = SquidMesh.Workflow.to_spec(SecurityCheck)

    trigger_names = Enum.map(spec.triggers, & &1.name)
    assert :security_check in trigger_names
    assert :scheduled_security_check in trigger_names

    assert Enum.map(spec.steps, & &1.name) == [:run_security_check]
  end

  test "bedrock scheduler enqueues the next schedule and a Squid Mesh payload job" do
    scheduled_for = ~U[2026-06-02 12:15:00Z]

    assert {:ok, :scheduled} =
             TheBeacon.BedrockScheduler.perform(
               %{
                 cron_expression: "*/15 * * * *",
                 scheduled_for: DateTime.to_iso8601(scheduled_for)
               },
               job_queue: FakeJobQueue,
               queue_id: "security",
               now: scheduled_for
             )

    assert_receive {:enqueued, "security", "beacon:schedule:security",
                    %{cron_expression: "*/15 * * * *", scheduled_for: "2026-06-02T12:30:00Z"},
                    [at: ~U[2026-06-02 12:30:00Z], id: "security-schedule:2026-06-02T12:30:00Z"]}

    assert_receive {:enqueued, "security", "squid_mesh:payload", payload, [id: payload_id]}

    assert payload_id == "security-check:2026-06-02T12:15:00Z"
    assert is_map(payload)
  end

  test "bedrock payload job delivers Squid Mesh payload and drains visible attempts" do
    assert :ok =
             TheBeacon.Jobs.SquidMeshPayload.perform(
               %{workflow: "security_check"},
               %{},
               runtime: FakeRuntime
             )

    assert_receive {:payload_delivered, %{workflow: "security_check"}}
    assert_receive :drained_once
  end

  test "schedule bootstrap seeds the next Bedrock schedule job" do
    assert {:ok, %{scheduled_for: ~U[2026-06-02 12:30:00Z]}} =
             TheBeacon.ScheduleBootstrap.seed(
               job_queue: FakeJobQueue,
               queue_id: "security",
               cron_expression: "*/15 * * * *",
               now: ~U[2026-06-02 12:16:00Z]
             )

    assert_receive {:enqueued, "security", "beacon:schedule:security",
                    %{cron_expression: "*/15 * * * *", scheduled_for: "2026-06-02T12:30:00Z"},
                    [at: ~U[2026-06-02 12:30:00Z], id: "security-schedule:2026-06-02T12:30:00Z"]}
  end

  test "application runtime children use Bedrock JobQueue instead of a local scheduler" do
    Application.put_env(:the_beacon, :start_runtime, true)

    on_exit(fn ->
      Application.delete_env(:the_beacon, :start_runtime)
    end)

    child_ids =
      TheBeacon.Application.runtime_children()
      |> Enum.map(fn
        {module, _opts} -> module
        module when is_atom(module) -> module
      end)

    assert TheBeacon.BedrockCluster in child_ids
    assert TheBeacon.JobQueue in child_ids
    assert TheBeacon.ScheduleBootstrap in child_ids
    refute TheBeacon.Scheduler in child_ids
    refute TheBeacon.Worker in child_ids
  end

  test "bedrock queue uses concrete Bedrock JobQueue workers" do
    assert %{
             otp_app: :the_beacon,
             repo: TheBeacon.BedrockRepo,
             workers: %{
               "beacon:schedule:security" => TheBeacon.Jobs.SecuritySchedule,
               "squid_mesh:payload" => TheBeacon.Jobs.SquidMeshPayload
             }
           } = TheBeacon.JobQueue.__config__()

    assert %{topic: "beacon:schedule:security", max_retries: 3, priority: 100} =
             TheBeacon.Jobs.SecuritySchedule.__job_config__()

    assert %{topic: "squid_mesh:payload", max_retries: 3, priority: 100} =
             TheBeacon.Jobs.SquidMeshPayload.__job_config__()
  end
end
