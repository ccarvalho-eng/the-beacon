defmodule TheBeacon.SeenStateFileTest do
  use ExUnit.Case, async: true

  alias TheBeacon.Event
  alias TheBeacon.SeenState.File, as: SeenFile

  test "stores seen event ids in a newline-delimited state file" do
    path =
      Path.join(System.tmp_dir!(), "the-beacon-seen-#{System.unique_integer([:positive])}.txt")

    on_exit(fn -> File.rm(path) end)

    events = [
      %Event{id: "B", source: "OSV", title: "b", url: "https://example.test/b"},
      %Event{id: "A", source: "OSV", title: "a", url: "https://example.test/a"}
    ]

    assert SeenFile.unseen(path, events) == events
    assert :ok = SeenFile.mark_seen(path, events)
    assert SeenFile.seen?(path, "A")
    assert SeenFile.seen?(path, "B")
    assert File.read!(path) == "A\nB\n"
  end
end
