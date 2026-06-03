defmodule TheBeacon.SecurityStepsTest do
  use ExUnit.Case, async: true

  alias TheBeacon.Event
  alias TheBeacon.SeenState.File, as: SeenFile
  alias TheBeacon.Steps.DeliverSecurityNotifications
  alias TheBeacon.Steps.FilterSeenEvents
  alias TheBeacon.Steps.MarkSeenEvents

  test "filter seen events keeps only advisories not present in the state file" do
    path = state_file()
    seen = %Event{id: "OSV-seen", source: "OSV", title: "seen", url: "https://osv.test/seen"}
    unseen = %Event{id: "GHSA-new", source: "GitHub", title: "new", url: "https://ghsa.test/new"}

    SeenFile.mark_seen(path, [seen])

    assert {:ok, %{events: [^unseen], checked_count: 2, new_count: 1}} =
             FilterSeenEvents.run(%{state_file: path, events: [seen, unseen]}, %{})
  end

  test "delivery failure is retryable and does not mark seen state" do
    original_webhooks = System.get_env("BEACON_WEBHOOKS")
    System.delete_env("BEACON_WEBHOOKS")

    on_exit(fn ->
      if original_webhooks do
        System.put_env("BEACON_WEBHOOKS", original_webhooks)
      end
    end)

    event = %Event{id: "GHSA-new", source: "GitHub", title: "new", url: "https://ghsa.test/new"}

    assert {:retry, :no_webhooks_configured} =
             DeliverSecurityNotifications.run(
               %{webhooks: [], events: [event], checked_count: 1, new_count: 1},
               %{}
             )
  end

  test "mark seen stores only delivered advisory ids and returns summary counts" do
    path = state_file()

    delivered = %Event{
      id: "GHSA-new",
      source: "GitHub",
      title: "new",
      url: "https://ghsa.test/new"
    }

    undelivered = "OSV-not-delivered"

    assert {:ok, %{checked_count: 2, new_count: 1, delivered_count: 1}} =
             MarkSeenEvents.run(
               %{
                 state_file: path,
                 events: [delivered],
                 checked_count: 2,
                 new_count: 1,
                 delivered_count: 1
               },
               %{}
             )

    assert SeenFile.seen?(path, delivered.id)
    refute SeenFile.seen?(path, undelivered)
  end

  defp state_file do
    path =
      Path.join(
        System.tmp_dir!(),
        "the-beacon-step-seen-#{System.unique_integer([:positive])}.txt"
      )

    on_exit(fn -> File.rm(path) end)

    path
  end
end
