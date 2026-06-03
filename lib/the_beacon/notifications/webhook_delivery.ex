defmodule TheBeacon.Notifications.WebhookDelivery do
  @moduledoc """
  Delivers monitor events to configured webhooks.
  """

  @behaviour TheBeacon.NotificationDelivery

  alias SquidMesh.Tools

  @impl true
  def deliver(events, opts) when is_list(events) do
    opts = normalize_opts(opts)

    case {events, opts.webhooks} do
      {[], _webhooks} ->
        :ok

      {[_ | _], []} ->
        {:error, :no_webhooks_configured}

      {[_ | _], webhooks} ->
        content = format(events)

        Enum.reduce_while(webhooks, :ok, fn webhook, :ok ->
          request = %{method: :post, url: webhook, json: %{content: content}}

          case Tools.invoke(opts.http_adapter, request, %{}) do
            {:ok, _result} -> {:cont, :ok}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)
    end
  end

  defp normalize_opts(opts) do
    opts = Map.new(opts)

    %{
      http_adapter: Map.get(opts, :http_adapter, SquidMesh.Tools.HTTP),
      webhooks: Map.get(opts, :webhooks, configured_webhooks())
    }
  end

  defp configured_webhooks do
    TheBeacon.Config.webhooks()
  end

  defp format(events) do
    lines = ["### New Elixir ecosystem vulnerability findings", ""]

    event_lines =
      Enum.flat_map(events, fn event ->
        title = truncate(event.title, 180)
        detail = if event.details, do: " (#{event.details})", else: ""

        [
          "- #{event.source}: #{event.id}#{detail}: #{title}",
          "  #{event.url}"
        ]
      end)

    Enum.join(lines ++ event_lines, "\n")
  end

  defp truncate(value, max) when byte_size(value) <= max, do: value
  defp truncate(value, max), do: binary_part(value, 0, max - 3) <> "..."
end
