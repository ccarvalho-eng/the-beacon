defmodule TheBeacon.Notifications.WebhookDelivery do
  @moduledoc """
  Delivers monitor events to configured webhooks.
  """

  @behaviour TheBeacon.NotificationDelivery

  alias SquidMesh.Tools

  @max_content_length 2_000
  @message_header "### New Elixir ecosystem vulnerability findings\n\n"

  @impl true
  def deliver(events, opts) when is_list(events) do
    opts = normalize_opts(opts)

    case {events, opts.webhooks} do
      {[], _webhooks} ->
        :ok

      {[_ | _], []} ->
        {:error, :no_webhooks_configured}

      {[_ | _], webhooks} ->
        messages = format(events)

        Enum.reduce_while(webhooks, :ok, fn webhook, :ok ->
          deliver_messages(webhook, messages, opts)
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

  defp deliver_messages(webhook, messages, opts) do
    messages
    |> Enum.reduce_while(:ok, fn content, :ok ->
      request = %{method: :post, url: webhook, json: %{content: content}}

      case Tools.invoke(opts.http_adapter, request, %{}) do
        {:ok, _result} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      :ok -> {:cont, :ok}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp format(events) do
    events
    |> Enum.map(&event_block/1)
    |> Enum.reduce([], &append_block/2)
    |> Enum.reverse()
  end

  defp append_block(block, []), do: [@message_header <> fit_block(block)]

  defp append_block(block, [current | rest]) do
    block = fit_block(block)
    candidate = current <> "\n" <> block

    if String.length(candidate) <= @max_content_length do
      [candidate | rest]
    else
      [@message_header <> block, current | rest]
    end
  end

  defp fit_block(block) do
    if String.length(@message_header <> block) <= @max_content_length do
      block
    else
      truncate(block, @max_content_length - String.length(@message_header))
    end
  end

  defp event_block(event) do
    title = truncate(event.title, 180)
    detail = if event.details, do: " (#{event.details})", else: ""

    Enum.join(
      [
        "- #{event.source}: #{event.id}#{detail}: #{title}",
        "  #{event.url}"
      ],
      "\n"
    )
  end

  defp truncate(value, max) when byte_size(value) <= max, do: value
  defp truncate(value, max), do: binary_part(value, 0, max - 3) <> "..."
end
