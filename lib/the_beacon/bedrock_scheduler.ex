defmodule TheBeacon.BedrockScheduler do
  @moduledoc false

  @topic "beacon:schedule:security"

  @spec perform(map(), keyword()) :: {:ok, :scheduled} | {:error, term()}
  def perform(payload, opts \\ []) do
    with {:ok, scheduled_for} <- fetch_scheduled_for(payload),
         {:ok, _schedule} <-
           enqueue_next_security_schedule(
             Keyword.put(opts, :now, DateTime.add(scheduled_for, 1, :second))
           ),
         {:ok, _payload} <-
           TheBeacon.BedrockDelivery.enqueue_security_check(delivery_opts(opts, scheduled_for)) do
      {:ok, :scheduled}
    end
  end

  @spec enqueue_next_security_schedule(keyword()) :: {:ok, map()} | {:error, term()}
  def enqueue_next_security_schedule(opts \\ []) do
    cron_expression = Keyword.get(opts, :cron_expression, TheBeacon.Config.security_cron())

    with {:ok, scheduled_for} <-
           next_run(cron_expression, Keyword.get(opts, :now, DateTime.utc_now())) do
      enqueue_schedule_job(cron_expression, scheduled_for, opts)
    end
  end

  @spec next_run(String.t(), DateTime.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def next_run(cron_expression, %DateTime{} = now) do
    with {:ok, cron} <- Crontab.CronExpression.Parser.parse(cron_expression),
         {:ok, next_run} <- Crontab.Scheduler.get_next_run_date(cron, DateTime.to_naive(now)) do
      {:ok, DateTime.from_naive!(next_run, "Etc/UTC")}
    end
  end

  defp enqueue_schedule_job(cron_expression, scheduled_for, opts) do
    job_queue = Keyword.get(opts, :job_queue, job_queue())
    queue_id = Keyword.get(opts, :queue_id, queue_id())

    payload = %{
      cron_expression: cron_expression,
      scheduled_for: DateTime.to_iso8601(scheduled_for)
    }

    job_opts = [at: scheduled_for, id: schedule_job_id(scheduled_for)]

    case job_queue.enqueue(queue_id, @topic, payload, job_opts) do
      {:ok, item} ->
        {:ok,
         %{
           item_id: item_id(item),
           scheduled_for: scheduled_for,
           queue: queue_id,
           topic: @topic
         }}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_enqueue_result, other}}
    end
  end

  defp fetch_scheduled_for(%{scheduled_for: scheduled_for}) when is_binary(scheduled_for) do
    case DateTime.from_iso8601(scheduled_for) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, {:invalid_scheduled_for, reason}}
    end
  end

  defp fetch_scheduled_for(%{"scheduled_for" => scheduled_for}) when is_binary(scheduled_for) do
    fetch_scheduled_for(%{scheduled_for: scheduled_for})
  end

  defp fetch_scheduled_for(payload), do: {:error, {:invalid_schedule_payload, payload}}

  defp item_id(%{id: id}), do: id

  defp delivery_opts(opts, scheduled_for) do
    opts
    |> Keyword.take([:job_queue, :queue_id])
    |> Keyword.put(:scheduled_for, scheduled_for)
  end

  defp schedule_job_id(scheduled_for) do
    "security-schedule:" <> DateTime.to_iso8601(scheduled_for)
  end

  defp job_queue do
    Application.get_env(:the_beacon, :job_queue, TheBeacon.JobQueue)
  end

  defp queue_id do
    Application.get_env(:the_beacon, :job_queue_id, "default")
  end
end
