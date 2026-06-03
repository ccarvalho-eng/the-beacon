defmodule TheBeacon.BedrockDelivery do
  @moduledoc false

  alias SquidMesh.Executor.Payload
  alias TheBeacon.Workflows.SecurityCheck

  @topic "squid_mesh:payload"

  @spec enqueue_security_check(keyword()) :: {:ok, map()} | {:error, term()}
  def enqueue_security_check(opts \\ []) do
    job_queue = Keyword.get(opts, :job_queue, job_queue())
    queue_id = Keyword.get(opts, :queue_id, queue_id())
    scheduled_for = Keyword.fetch!(opts, :scheduled_for)
    signal_id = security_signal_id(scheduled_for)

    payload =
      Payload.cron(SecurityCheck, :scheduled_security_check,
        signal_id: signal_id,
        intended_window: intended_window(scheduled_for)
      )

    case job_queue.enqueue(queue_id, @topic, raw_payload(payload), id: signal_id) do
      {:ok, item} -> {:ok, metadata(item, queue_id, @topic)}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_enqueue_result, other}}
    end
  end

  defp raw_payload(payload) do
    %{raw: Jason.encode!(payload)}
  end

  defp intended_window(scheduled_for) do
    iso8601 = DateTime.to_iso8601(scheduled_for)
    %{"start_at" => iso8601, "end_at" => iso8601}
  end

  defp security_signal_id(scheduled_for) do
    "security-check:" <> DateTime.to_iso8601(scheduled_for)
  end

  defp metadata(item, queue_id, topic) do
    %{
      item_id: item_id(item),
      queue: queue_id,
      topic: topic,
      adapter: __MODULE__
    }
  end

  defp item_id(%{id: id}), do: id

  defp job_queue do
    Application.get_env(:the_beacon, :job_queue, TheBeacon.JobQueue)
  end

  defp queue_id do
    TheBeacon.JobQueue.queue_id()
  end
end
