defmodule TheBeacon.SecurityCheck do
  @moduledoc """
  Runs the Beacon security monitor loop.
  """

  @type opts :: %{
          required(:monitor) => module(),
          required(:delivery) => module(),
          required(:seen_state) => term(),
          optional(atom()) => term()
        }

  @spec run(opts()) :: {:ok, map()} | {:error, term()}
  def run(%{monitor: monitor, delivery: delivery, seen_state: seen_state} = opts) do
    seen_state_module = Map.get(opts, :seen_state_module, TheBeacon.SeenState.Memory)

    with {:ok, events} <- check(monitor, opts),
         unseen_events <- seen_state_module.unseen(seen_state, events),
         :ok <- deliver_if_needed(delivery, unseen_events, opts) do
      seen_state_module.mark_seen(seen_state, unseen_events)

      {:ok,
       %{
         checked_count: length(events),
         new_count: length(unseen_events),
         delivered_count: length(unseen_events)
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp check(monitor, opts) do
    case monitor.check(opts) do
      {:ok, events} when is_list(events) -> {:ok, events}
      events when is_list(events) -> {:ok, events}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_if_needed(_delivery, [], _opts), do: :ok
  defp deliver_if_needed(delivery, events, opts), do: delivery.deliver(events, opts)
end
