defmodule TheBeacon.Steps.FetchSecurityEvents do
  @moduledoc """
  Fetches security advisory events from all configured monitor sources.
  """

  use Squidie.Step,
    name: :fetch_security_events,
    description: "Fetches and normalizes Elixir ecosystem security advisories",
    input_schema: [],
    output_schema: [
      events: [type: :list, required: true]
    ]

  require Logger

  @impl true
  def run(_input, _context) do
    Logger.info("Fetching security events")

    case TheBeacon.Monitors.Security.check(%{}) do
      {:ok, events} ->
        Logger.info("Fetched #{length(events)} security events")
        {:ok, %{events: events}}

      {:error, reason} ->
        Logger.warning("Security event fetch failed: #{inspect(reason)}")
        {:retry, reason}
    end
  end
end
