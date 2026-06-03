defmodule TheBeacon.Runtime do
  @moduledoc """
  Host-owned boundary for starting and draining Beacon Squid Mesh work.
  """

  alias SquidMesh.Runtime.Runner

  @spec configure_squid_mesh!() :: :ok
  def configure_squid_mesh! do
    Enum.each(squid_mesh_opts(), fn {key, value} ->
      Application.put_env(:squid_mesh, key, value)
    end)
  end

  @spec deliver_payload(map()) :: :ok | {:ok, term()} | {:error, term()}
  def deliver_payload(payload) when is_map(payload) do
    Runner.perform(payload, squid_mesh_opts())
  end

  @spec drain_once(keyword()) :: SquidMesh.Executor.execute_result()
  def drain_once(opts \\ []) do
    SquidMesh.execute_next(execute_next_opts(opts))
  end

  @doc false
  @spec execute_next_opts(keyword()) :: keyword()
  def execute_next_opts(opts \\ []) do
    squid_mesh_opts()
    |> Keyword.take([:runtime, :journal_storage, :queue])
    |> Keyword.merge(opts)
    |> Keyword.put_new(:owner_id, "the-beacon")
  end

  @spec squid_mesh_opts() :: keyword()
  def squid_mesh_opts do
    [
      repo: TheBeacon.BedrockRepo,
      journal_storage:
        {Jido.Storage.File,
         path:
           Application.get_env(:the_beacon, :squid_mesh_journal_path, "tmp/squid_mesh_journal")}
    ]
  end
end
