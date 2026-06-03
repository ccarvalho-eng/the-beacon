defmodule TheBeacon.Steps.RunSecurityCheck do
  @moduledoc """
  Runs the Beacon security check inside a Squid Mesh workflow step.
  """

  use SquidMesh.Step,
    name: :run_security_check,
    description: "Fetches advisories, sends webhook notifications, and persists delivered IDs",
    input_schema: [
      state_file: [type: :string, required: true],
      webhooks: [type: :list, required: false]
    ],
    output_schema: [
      security_check: [type: :map, required: true]
    ]

  @impl true
  def run(input, _context) do
    opts =
      %{
        state_file: state_file(input),
        webhooks: webhooks(input)
      }
      |> Map.merge(%{
        monitor: TheBeacon.Monitors.Security,
        delivery: TheBeacon.Notifications.WebhookDelivery,
        seen_state_module: TheBeacon.SeenState.File,
        seen_state: state_file(input)
      })

    case TheBeacon.SecurityCheck.run(opts) do
      {:ok, result} -> {:ok, %{security_check: result}}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp state_file(%{state_file: ""}), do: TheBeacon.Config.security_state_file()
  defp state_file(%{state_file: state_file}), do: state_file
  defp state_file(_input), do: TheBeacon.Config.security_state_file()

  defp webhooks(%{webhooks: [_ | _] = webhooks}), do: webhooks
  defp webhooks(_input), do: TheBeacon.Config.webhooks()
end
