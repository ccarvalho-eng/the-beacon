defmodule TheBeacon.Jobs.SquidMeshPayload do
  @moduledoc false

  use Bedrock.JobQueue.Job,
    topic: "squid_mesh:payload",
    max_retries: 3,
    priority: 100

  @default_max_journal_attempts 50
  @default_journal_heartbeat_interval_ms 10_000

  @impl true
  def perform(payload, meta), do: perform(payload, meta, [])

  @spec perform(map(), map(), keyword()) :: :ok | {:error, term()}
  def perform(payload, _meta, opts) when is_map(payload) do
    runtime = Keyword.get(opts, :runtime, TheBeacon.Runtime)

    with {:ok, payload} <- normalize_payload(payload) do
      case runtime.deliver_payload(payload) do
        :ok -> drain_journal_attempts(runtime, 0)
        {:ok, _snapshot} -> drain_journal_attempts(runtime, 0)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp normalize_payload(%{raw: raw}) when is_binary(raw), do: decode_raw_payload(raw)
  defp normalize_payload(%{"raw" => raw}) when is_binary(raw), do: decode_raw_payload(raw)
  defp normalize_payload(payload), do: {:ok, payload}

  defp decode_raw_payload(raw) do
    case Jason.decode(raw) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, _payload} -> {:error, {:invalid_runtime_payload, :expected_map}}
      {:error, reason} -> {:error, {:invalid_runtime_payload, reason}}
    end
  end

  defp drain_journal_attempts(runtime, count) do
    if count >= max_journal_attempts() do
      {:error, :journal_drain_limit_exceeded}
    else
      case drain_once(runtime) do
        {:ok, :none} -> :ok
        {:ok, _snapshot} -> drain_journal_attempts(runtime, count + 1)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp drain_once(runtime) do
    opts = [
      owner_id: "the-beacon-bedrock-worker",
      heartbeat_interval_ms: journal_heartbeat_interval_ms()
    ]

    if function_exported?(runtime, :drain_once, 1) do
      runtime.drain_once(opts)
    else
      runtime.drain_once()
    end
  end

  defp journal_heartbeat_interval_ms do
    :the_beacon
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:journal_heartbeat_interval_ms, @default_journal_heartbeat_interval_ms)
  end

  defp max_journal_attempts do
    :the_beacon
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:max_journal_attempts, @default_max_journal_attempts)
  end
end
