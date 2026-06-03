defmodule TheBeacon.JobQueue do
  @moduledoc false

  @queue_id "security"

  use Bedrock.JobQueue,
    otp_app: :the_beacon,
    repo: TheBeacon.BedrockRepo,
    workers: %{
      "beacon:schedule:security" => TheBeacon.Jobs.SecuritySchedule,
      "squidie:payload" => TheBeacon.Jobs.SquidiePayload
    }

  @spec queue_id() :: String.t()
  def queue_id, do: @queue_id
end
