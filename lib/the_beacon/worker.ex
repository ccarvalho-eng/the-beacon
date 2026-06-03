defmodule TheBeacon.Worker do
  @moduledoc """
  Generic Squid Mesh worker loop for the standalone OTP app.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    state = %{
      runtime: Keyword.get(opts, :runtime, TheBeacon.Runtime),
      idle_backoff_ms: Keyword.get(opts, :idle_backoff_ms, 1_000)
    }

    send(self(), :drain)
    {:ok, state}
  end

  @impl true
  def handle_info(:drain, state) do
    case state.runtime.drain_once() do
      {:ok, :none} -> schedule_drain(state.idle_backoff_ms)
      _result -> schedule_drain(0)
    end

    {:noreply, state}
  end

  defp schedule_drain(interval_ms) do
    Process.send_after(self(), :drain, interval_ms)
  end
end
