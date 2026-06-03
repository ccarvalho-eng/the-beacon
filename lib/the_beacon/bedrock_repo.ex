defmodule TheBeacon.BedrockRepo do
  @moduledoc false

  use Bedrock.Repo, cluster: TheBeacon.BedrockCluster
end
