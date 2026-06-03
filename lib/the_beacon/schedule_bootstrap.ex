defmodule TheBeacon.ScheduleBootstrap do
  @moduledoc false

  use Task

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts) do
    Task.start_link(fn ->
      case seed(opts) do
        {:ok, _metadata} -> :ok
        {:error, reason} -> raise "failed to seed Beacon schedule: #{inspect(reason)}"
      end
    end)
  end

  @spec seed(keyword()) :: {:ok, map()} | {:error, term()}
  def seed(opts \\ []) do
    TheBeacon.BedrockScheduler.enqueue_next_security_schedule(opts)
  end
end
