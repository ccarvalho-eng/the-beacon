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

    assert Enum.all?(
             spec.triggers,
             &(&1.payload == [
                 %{name: :state_file, opts: [default: "state/security-seen.txt"], type: :string}
               ])
           )

    assert Enum.map(spec.steps, & &1.name) == [
             :log_security_check_started,
             :fetch_security_events,
             :filter_seen_events,
             :deliver_security_notifications,
             :mark_seen_events,
             :log_security_check_completed
           ]

    assert %{
             module: :log,
             opts: [message: "Security check started", level: :info]
           } = Enum.find(spec.steps, &(&1.name == :log_security_check_started))

    assert %{
             module: :log,
             opts: [message: "Security check completed", level: :info]
           } = Enum.find(spec.steps, &(&1.name == :log_security_check_completed))

    delivery_step = Enum.find(spec.steps, &(&1.name == :deliver_security_notifications))
    assert Keyword.fetch!(delivery_step.opts, :irreversible) == true

    assert Enum.map(spec.transitions, &{&1.from, &1.on, &1.to}) == [
             {:log_security_check_started, :ok, :fetch_security_events},
             {:fetch_security_events, :ok, :filter_seen_events},
             {:filter_seen_events, :ok, :deliver_security_notifications},
             {:deliver_security_notifications, :ok, :mark_seen_events},
             {:mark_seen_events, :ok, :log_security_check_completed},
             {:log_security_check_completed, :ok, :complete}
           ]
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
    assert %{raw: raw} = Bedrock.JobQueue.Payload.decode(Jason.encode!(payload))

    assert raw == Map.fetch!(payload, :raw)
    assert {:ok, cron_payload} = Jason.decode(Map.fetch!(payload, :raw))
    assert cron_payload["kind"] == "cron"
    assert cron_payload["trigger"] == "scheduled_security_check"
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

  test "bedrock payload job decodes raw JSON payloads from JobQueue fallback" do
    payload =
      SquidMesh.Executor.Payload.cron(SecurityCheck, :scheduled_security_check,
        signal_id: "security-check:2026-06-02T12:15:00Z",
        intended_window: %{
          "start_at" => "2026-06-02T12:15:00Z",
          "end_at" => "2026-06-02T12:15:00Z"
        }
      )

    assert :ok =
             TheBeacon.Jobs.SquidMeshPayload.perform(
               %{raw: Jason.encode!(payload)},
               %{},
               runtime: FakeRuntime
             )

    assert_receive {:payload_delivered, ^payload}
    assert_receive :drained_once
  end

  test "schedule bootstrap seeds from the workflow cron definition" do
    assert {:ok, %{scheduled_for: ~U[2026-06-02 12:30:00Z]}} =
             TheBeacon.ScheduleBootstrap.seed(
               job_queue: FakeJobQueue,
               queue_id: "security",
               now: ~U[2026-06-02 12:16:00Z]
             )

    assert_receive {:enqueued, "security", "beacon:schedule:security",
                    %{cron_expression: "*/15 * * * *", scheduled_for: "2026-06-02T12:30:00Z"},
                    [at: ~U[2026-06-02 12:30:00Z], id: "security-schedule:2026-06-02T12:30:00Z"]}
  end

  test "bedrock producers default to the security queue" do
    scheduled_for = ~U[2026-06-02 12:15:00Z]

    assert {:ok, %{queue: "security"}} =
             TheBeacon.BedrockScheduler.enqueue_next_security_schedule(
               job_queue: FakeJobQueue,
               now: scheduled_for
             )

    assert_receive {:enqueued, "security", "beacon:schedule:security", _payload, _opts}

    assert {:ok, %{queue: "security"}} =
             TheBeacon.BedrockDelivery.enqueue_security_check(
               job_queue: FakeJobQueue,
               scheduled_for: scheduled_for
             )

    assert_receive {:enqueued, "security", "squid_mesh:payload", _payload, _opts}
  end

  test "application runtime children start by default with Bedrock JobQueue" do
    child_ids =
      Enum.map(TheBeacon.Application.runtime_children(), fn
        {module, _opts} -> module
        module when is_atom(module) -> module
      end)

    assert TheBeacon.BedrockCluster in child_ids
    assert TheBeacon.JobQueue in child_ids
    assert TheBeacon.ScheduleBootstrap in child_ids
    refute TheBeacon.Scheduler in child_ids
    refute TheBeacon.Worker in child_ids
  end

  test "application configures Squid Mesh runtime for manual workflow starts" do
    previous_repo = Application.get_env(:squid_mesh, :repo)
    previous_journal_storage = Application.get_env(:squid_mesh, :journal_storage)

    Application.delete_env(:squid_mesh, :repo)
    Application.delete_env(:squid_mesh, :journal_storage)

    on_exit(fn ->
      restore_env(:repo, previous_repo)
      restore_env(:journal_storage, previous_journal_storage)
    end)

    TheBeacon.Runtime.configure_squid_mesh!()

    assert Application.get_env(:squid_mesh, :repo) == TheBeacon.BedrockRepo

    assert {Jido.Storage.File, path: "tmp/squid_mesh_journal"} =
             Application.get_env(:squid_mesh, :journal_storage)
  end

  test "runtime drains with public Squid Mesh execute options" do
    opts =
      TheBeacon.Runtime.execute_next_opts(owner_id: "test-worker", heartbeat_interval_ms: 1_000)

    refute Keyword.has_key?(opts, :repo)
    assert Keyword.fetch!(opts, :owner_id) == "test-worker"
    assert Keyword.fetch!(opts, :heartbeat_interval_ms) == 1_000

    assert {Jido.Storage.File, path: "tmp/squid_mesh_journal"} =
             Keyword.fetch!(opts, :journal_storage)
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

  defp restore_env(_key, nil), do: :ok
  defp restore_env(key, value), do: Application.put_env(:squid_mesh, key, value)
end
