defmodule TheBeacon.WorkflowTest do
  use ExUnit.Case, async: false

  alias TheBeacon.Workflows.SecurityCheck

  defmodule FakeRuntime do
    def start_security_check do
      send(:persistent_term.get({__MODULE__, :owner}), :security_check_started)
      :ok
    end

    def drain_once do
      send(:persistent_term.get({__MODULE__, :owner}), :drained_once)
      {:ok, :none}
    end
  end

  setup do
    :persistent_term.put({FakeRuntime, :owner}, self())
    :ok
  end

  test "security workflow exposes manual and scheduled security check triggers" do
    assert {:ok, spec} = SquidMesh.Workflow.to_spec(SecurityCheck)

    trigger_names = Enum.map(spec.triggers, & &1.name)
    assert :security_check in trigger_names
    assert :scheduled_security_check in trigger_names

    assert Enum.map(spec.steps, & &1.name) == [:run_security_check]
  end

  test "scheduler starts a security check on tick" do
    {:ok, scheduler} =
      start_supervised(
        {TheBeacon.Scheduler, runtime: FakeRuntime, interval_ms: 60_000, name: nil}
      )

    send(scheduler, :tick)

    assert_receive :security_check_started
  end

  test "worker drains Squid Mesh work" do
    {:ok, worker} =
      start_supervised(
        {TheBeacon.Worker, runtime: FakeRuntime, idle_backoff_ms: 60_000, name: nil}
      )

    send(worker, :drain)

    assert_receive :drained_once
  end
end
