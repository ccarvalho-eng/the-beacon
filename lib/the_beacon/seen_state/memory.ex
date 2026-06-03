defmodule TheBeacon.SeenState.Memory do
  @moduledoc """
  In-memory seen-state store for tests and local smoke runs.
  """

  use Agent

  @type id :: String.t()

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts) do
    seen_ids =
      opts
      |> Keyword.get(:seen_ids, [])
      |> MapSet.new()

    Agent.start_link(fn -> seen_ids end)
  end

  @spec unseen(pid(), [TheBeacon.Event.t()]) :: [TheBeacon.Event.t()]
  def unseen(pid, events) when is_pid(pid) and is_list(events) do
    Agent.get(pid, fn seen_ids ->
      Enum.reject(events, fn event -> MapSet.member?(seen_ids, event_id(event)) end)
    end)
  end

  @spec mark_seen(pid(), [id()] | [TheBeacon.Event.t()]) :: :ok
  def mark_seen(pid, ids_or_events) when is_pid(pid) and is_list(ids_or_events) do
    ids = Enum.map(ids_or_events, &event_id/1)

    Agent.update(pid, fn seen_ids ->
      Enum.reduce(ids, seen_ids, &MapSet.put(&2, &1))
    end)
  end

  @spec seen?(pid(), id()) :: boolean()
  def seen?(pid, id) when is_pid(pid) and is_binary(id) do
    Agent.get(pid, &MapSet.member?(&1, id))
  end

  defp event_id(%TheBeacon.Event{id: id}), do: id
  defp event_id(%{id: id}) when is_binary(id), do: id
  defp event_id(%{"id" => id}) when is_binary(id), do: id
  defp event_id(id) when is_binary(id), do: id
end
