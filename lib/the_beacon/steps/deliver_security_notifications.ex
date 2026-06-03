defmodule TheBeacon.Steps.DeliverSecurityNotifications do
  @moduledoc """
  Delivers unseen security advisories to configured webhooks.
  """

  use SquidMesh.Step,
    name: :deliver_security_notifications,
    description: "Sends webhook notifications for unseen security advisories",
    input_schema: [
      webhooks: [type: :list, required: false],
      events: [type: :list, required: true],
      checked_count: [type: :integer, required: true],
      new_count: [type: :integer, required: true]
    ],
    output_schema: [
      events: [type: :list, required: true],
      checked_count: [type: :integer, required: true],
      new_count: [type: :integer, required: true],
      delivered_count: [type: :integer, required: true]
    ]

  @impl true
  def run(%{events: events} = input, _context) do
    opts = %{webhooks: webhooks(input)}

    case TheBeacon.Notifications.WebhookDelivery.deliver(events, opts) do
      :ok ->
        {:ok,
         %{
           events: events,
           checked_count: input.checked_count,
           new_count: input.new_count,
           delivered_count: length(events)
         }}

      {:error, reason} ->
        {:retry, reason}
    end
  end

  defp webhooks(%{webhooks: [_ | _] = webhooks}), do: webhooks
  defp webhooks(_input), do: TheBeacon.Config.webhooks()
end
