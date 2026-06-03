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

  @impl true
  def run(%{events: events} = input, _context) do
    if events != [] do
      TheBeacon.SeenState.File.mark_seen(state_file(input), events)
    end

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
