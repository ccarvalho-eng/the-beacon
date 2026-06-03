defmodule TheBeacon.Config do
  @moduledoc """
  Runtime configuration for the standalone Beacon OTP app.
  """

  @spec webhooks() :: [String.t()]
  def webhooks do
    case System.get_env("BEACON_WEBHOOKS") do
      nil -> []
      "" -> []
      value -> Jason.decode!(value)
    end
  end
end
