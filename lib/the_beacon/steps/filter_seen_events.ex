defmodule TheBeacon.Steps.FilterSeenEvents do
  @moduledoc """
  Filters fetched advisory events against the file-backed seen-state store.
  """

  @default_state_file "state/security-seen.txt"

  use SquidMesh.Step,
    name: :filter_seen_events,
    description: "Filters advisories that were already delivered",
    input_schema: [
      state_file: [type: :string, required: true],
      events: [type: :list, required: true]
    ],
    output_schema: [
      events: [type: :list, required: true],
      checked_count: [type: :integer, required: true],
      new_count: [type: :integer, required: true]
    ]

  require Logger

  @impl true
  def run(%{events: events} = input, _context) do
    state_file = state_file(input)
    unseen_events = TheBeacon.SeenState.File.unseen(state_file, events)

    Logger.info(
      "Filtered security events against seen state",
      checked_count: length(events),
      new_count: length(unseen_events),
      state_file: state_file
    )

    {:ok,
     %{
       events: unseen_events,
       checked_count: length(events),
       new_count: length(unseen_events)
     }}
  end

  defp state_file(%{state_file: ""}), do: @default_state_file
  defp state_file(%{state_file: state_file}), do: state_file
end
