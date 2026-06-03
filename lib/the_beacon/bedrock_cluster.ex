defmodule TheBeacon.BedrockCluster do
  @moduledoc false

  use Bedrock.Cluster,
    otp_app: :the_beacon,
    name: "the_beacon",
    config: [
      capabilities: [:coordination, :log, :storage],
      durability_mode: :relaxed,
      trace: [],
      coordinator: [path: "tmp/bedrock_runtime"],
      storage: [path: "tmp/bedrock_runtime"],
      log: [path: "tmp/bedrock_runtime"]
    ]
end
