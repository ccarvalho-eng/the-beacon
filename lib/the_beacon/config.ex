defmodule TheBeacon.Config do
  @moduledoc """
  Runtime configuration for the standalone Beacon OTP app.
  """

  @default_security_cron "*/15 * * * *"
  @default_state_file "state/security-seen.txt"

  @spec webhooks() :: [String.t()]
  def webhooks do
    case System.get_env("BEACON_WEBHOOKS") do
      nil -> []
      "" -> []
      value -> Jason.decode!(value)
    end
  end

  @spec security_cron() :: String.t()
  def security_cron do
    System.get_env("BEACON_SECURITY_CRON", @default_security_cron)
  end

  @spec security_state_file() :: String.t()
  def security_state_file do
    System.get_env("BEACON_SECURITY_STATE_FILE", @default_state_file)
  end
end
