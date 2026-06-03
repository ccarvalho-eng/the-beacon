defmodule TheBeacon.Jobs.SecuritySchedule do
  @moduledoc false

  use Bedrock.JobQueue.Job,
    topic: "beacon:schedule:security",
    max_retries: 3,
    priority: 100

  @impl true
  def perform(payload, _meta) when is_map(payload) do
    TheBeacon.BedrockScheduler.perform(payload)
  end
end
