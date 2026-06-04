defmodule TheBeacon.Runtime do
  @moduledoc """
  Host-owned boundary for starting and draining Beacon Squidie work.
  """

  alias Squidie.Runtime.Runner

  @spec configure_squidie!() :: :ok
  def configure_squidie! do
    Enum.each(squidie_opts(), fn {key, value} ->
      Application.put_env(:squidie, key, value)
    end)
  end

  @spec deliver_payload(map()) :: :ok | {:ok, term()} | {:error, term()}
  def deliver_payload(payload) when is_map(payload) do
    Runner.perform(payload, squidie_opts())
  end

  @spec drain_once(keyword()) :: Squidie.Executor.execute_result()
  def drain_once(opts \\ []) do
    Squidie.execute_next(execute_next_opts(opts))
  end

  @doc false
  @spec execute_next_opts(keyword()) :: keyword()
  def execute_next_opts(opts \\ []) do
    squidie_opts()
    |> Keyword.take([:runtime, :journal_storage, :queue])
    |> Keyword.merge(opts)
    |> Keyword.put_new(:owner_id, "the-beacon")
  end

  @spec squidie_opts() :: keyword()
  def squidie_opts do
    [
      repo: TheBeacon.BedrockRepo,
      journal_storage:
        {Jido.Storage.File,
         path: Application.get_env(:the_beacon, :squidie_journal_path, "tmp/squidie_journal")}
    ]
  end
end
