defmodule TheBeacon.JobQueue do
  @moduledoc false

  use Bedrock.JobQueue,
    otp_app: :the_beacon,
    repo: TheBeacon.BedrockRepo,
    workers: %{
      "beacon:schedule:security" => TheBeacon.Jobs.SecuritySchedule,
      "squid_mesh:payload" => TheBeacon.Jobs.SquidMeshPayload
    }
end
