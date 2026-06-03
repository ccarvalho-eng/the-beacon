defmodule TheBeacon.Scheduler do
  @moduledoc """
  Minimal OTP scheduler for Beacon security checks.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms),
      cron_expression: Keyword.get(opts, :cron_expression, TheBeacon.Config.security_cron()),
      runtime: Keyword.get(opts, :runtime, TheBeacon.Runtime)
    }

    schedule_tick(next_interval_ms(state))
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    _result = state.runtime.start_security_check()
    schedule_tick(next_interval_ms(state))
    {:noreply, state}
  end

  defp next_interval_ms(%{interval_ms: interval_ms}) when is_integer(interval_ms), do: interval_ms

  defp next_interval_ms(%{cron_expression: expression}) do
    {:ok, cron} = Crontab.CronExpression.Parser.parse(expression)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    {:ok, next_run} = Crontab.Scheduler.get_next_run_date(cron, now)

    max(NaiveDateTime.diff(next_run, now, :millisecond), 1_000)
  end

  defp schedule_tick(interval_ms) do
    Process.send_after(self(), :tick, interval_ms)
  end
end
