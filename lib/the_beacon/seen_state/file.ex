defmodule TheBeacon.SeenState.File do
  @moduledoc """
  File-backed seen-state store for the standalone OTP app.
  """

  alias TheBeacon.Event

  @type path :: String.t()

  @spec unseen(path(), [Event.t()]) :: [Event.t()]
  def unseen(path, events) when is_binary(path) and is_list(events) do
    seen_ids = read(path)
    Enum.reject(events, fn event -> MapSet.member?(seen_ids, event_id(event)) end)
  end

  @spec mark_seen(path(), [String.t()] | [Event.t()]) :: :ok
  def mark_seen(path, ids_or_events) when is_binary(path) and is_list(ids_or_events) do
    ids = Enum.map(ids_or_events, &event_id/1)

    updated_ids =
      path
      |> read()
      |> then(fn seen_ids -> Enum.reduce(ids, seen_ids, &MapSet.put(&2, &1)) end)
      |> Enum.sort()

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, Enum.join(updated_ids, "\n") <> "\n")
  end

  @spec seen?(path(), String.t()) :: boolean()
  def seen?(path, id) when is_binary(path) and is_binary(id) do
    path
    |> read()
    |> MapSet.member?(id)
  end

  defp read(path) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> MapSet.new()

      {:error, :enoent} ->
        MapSet.new()
    end
  end

  defp event_id(%Event{id: id}), do: id
  defp event_id(%{id: id}) when is_binary(id), do: id
  defp event_id(%{"id" => id}) when is_binary(id), do: id
  defp event_id(id) when is_binary(id), do: id
end
