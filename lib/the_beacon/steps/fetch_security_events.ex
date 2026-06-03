defmodule TheBeacon.Steps.FetchSecurityEvents do
  @moduledoc """
  Fetches security advisory events from all configured monitor sources.
  """

  use SquidMesh.Step,
    name: :fetch_security_events,
    description: "Fetches and normalizes Elixir ecosystem security advisories",
    input_schema: [],
    output_schema: [
      events: [type: :list, required: true]
    ]

  @impl true
  def run(_input, _context) do
    case TheBeacon.Monitors.Security.check(%{}) do
      {:ok, events} -> {:ok, %{events: events}}
      {:error, reason} -> {:retry, reason}
    end
  end
end
