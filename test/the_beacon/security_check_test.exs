defmodule TheBeacon.SecurityCheckTest do
  use ExUnit.Case, async: true

  alias TheBeacon.Event
  alias TheBeacon.SecurityCheck
  alias TheBeacon.SeenState.Memory

  defmodule FakeMonitor do
    @behaviour TheBeacon.Monitor

    @impl true
    def check(_opts) do
      [
        %Event{
          id: "GHSA-new",
          source: "GitHub Advisory Database",
          title: "new advisory",
          url: "https://github.com/advisories/GHSA-new",
          details: "new issue"
        },
        %Event{
          id: "OSV-seen",
          source: "OSV",
          title: "old advisory",
          url: "https://osv.dev/vulnerability/OSV-seen",
          details: "already delivered"
        }
      ]
    end
  end

  defmodule SuccessfulDelivery do
    @behaviour TheBeacon.NotificationDelivery

    @impl true
    def deliver(events, _opts) do
      send(self(), {:delivered, Enum.map(events, & &1.id)})
      :ok
    end
  end

  defmodule FailingDelivery do
    @behaviour TheBeacon.NotificationDelivery

    @impl true
    def deliver(_events, _opts), do: {:error, :webhook_down}
  end

  setup do
    {:ok, seen} = start_supervised({Memory, seen_ids: ["OSV-seen"]})
    %{seen: seen}
  end

  test "delivers only unseen events and marks them seen after delivery succeeds", %{seen: seen} do
    assert {:ok, %{new_count: 1, delivered_count: 1}} =
             SecurityCheck.run(%{
               monitor: FakeMonitor,
               delivery: SuccessfulDelivery,
               seen_state: seen
             })

    assert_receive {:delivered, ["GHSA-new"]}
    assert Memory.seen?(seen, "GHSA-new")
    assert Memory.seen?(seen, "OSV-seen")
  end

  test "does not mark unseen events when delivery fails", %{seen: seen} do
    assert {:error, :webhook_down} =
             SecurityCheck.run(%{
               monitor: FakeMonitor,
               delivery: FailingDelivery,
               seen_state: seen
             })

    refute Memory.seen?(seen, "GHSA-new")
    assert Memory.seen?(seen, "OSV-seen")
  end
end
