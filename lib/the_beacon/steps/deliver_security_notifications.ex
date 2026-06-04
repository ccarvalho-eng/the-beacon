defmodule TheBeacon.Steps.DeliverSecurityNotifications do
  @moduledoc """
  Delivers unseen security advisories to configured webhooks.
  """

  use Squidie.Step,
    name: :deliver_security_notifications,
    description: "Sends webhook notifications for unseen security advisories",
    input_schema: [
      state_file: [type: :string, required: true],
      events: [type: :list, required: true],
      checked_count: [type: :integer, required: true],
      new_count: [type: :integer, required: true]
    ],
    output_schema: [
      state_file: [type: :string, required: true],
      events: [type: :list, required: true],
      checked_count: [type: :integer, required: true],
      new_count: [type: :integer, required: true],
      delivered_count: [type: :integer, required: true]
    ]

  require Logger

  @impl true
  def run(%{events: events} = input, _context) do
    Logger.info(
      "Delivering security notifications",
      checked_count: input.checked_count,
      new_count: input.new_count,
      event_count: length(events)
    )

    case TheBeacon.Notifications.WebhookDelivery.deliver(events, %{}) do
      :ok ->
        Logger.info("Delivered security notifications", delivered_count: length(events))

        {:ok,
         %{
           state_file: input.state_file,
           events: events,
           checked_count: input.checked_count,
           new_count: input.new_count,
           delivered_count: length(events)
         }}

      {:error, reason} ->
        Logger.warning("Security notification delivery failed: #{safe_inspect(reason)}")
        {:retry, reason}
    end
  end

  defp safe_inspect(term) do
    redacted = redact(term)
    inspect(redacted, limit: 20, printable_limit: 1_000)
  end

  defp redact(term) when is_binary(term) do
    Regex.replace(
      ~r"https://(?:discord(?:app)?\.com|canary\.discord\.com)/api/webhooks/[^\s\"'<>]+",
      term,
      "[REDACTED_DISCORD_WEBHOOK]"
    )
  end

  defp redact(term) when is_list(term), do: Enum.map(term, &redact/1)

  defp redact(term) when is_map(term) do
    Map.new(term, fn {key, value} -> {key, redact(value)} end)
  end

  defp redact(term) when is_tuple(term) do
    list = Tuple.to_list(term)
    redacted = redact(list)
    List.to_tuple(redacted)
  end

  defp redact(term), do: term
end
