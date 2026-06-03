defmodule TheBeacon.Steps.MarkSeenEvents do
  @moduledoc """
  Marks delivered security advisories as seen.
  """

  @default_state_file "state/security-seen.txt"

  use SquidMesh.Step,
    name: :mark_seen_events,
    description: "Persists delivered advisory IDs to the seen-state file",
    input_schema: [
      state_file: [type: :string, required: true],
      events: [type: :list, required: true],
      checked_count: [type: :integer, required: true],
      new_count: [type: :integer, required: true],
      delivered_count: [type: :integer, required: true]
    ],
    output_schema: [
      checked_count: [type: :integer, required: true],
      new_count: [type: :integer, required: true],
      delivered_count: [type: :integer, required: true]
    ]

  require Logger

  @impl true
  def run(%{events: events} = input, _context) do
    state_file = state_file(input)

    if events != [] do
      Logger.info("Marking security events seen", count: length(events), state_file: state_file)
      TheBeacon.SeenState.File.mark_seen(state_file, events)
    else
      Logger.info("No security events to mark seen", state_file: state_file)
    end

    Logger.info(
      "Finished marking security events seen",
      checked_count: input.checked_count,
      new_count: input.new_count,
      delivered_count: input.delivered_count,
      state_file: state_file
    )

    {:ok,
     %{
       checked_count: input.checked_count,
       new_count: input.new_count,
       delivered_count: input.delivered_count
     }}
  end

  defp state_file(%{state_file: ""}), do: @default_state_file
  defp state_file(%{state_file: state_file}), do: state_file
end
