defmodule TheBeacon.Runtime do
  @moduledoc """
  Host-owned boundary for starting and draining Beacon Squid Mesh work.
  """

  alias SquidMesh.Runtime.Runner

  @spec deliver_payload(map()) :: :ok | {:ok, term()} | {:error, term()}
  def deliver_payload(payload) when is_map(payload) do
    Runner.perform(payload, squid_mesh_opts())
  end

  @spec drain_once(keyword()) :: SquidMesh.Executor.execute_result()
  def drain_once(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:owner_id, "the-beacon")
      |> Keyword.merge(squid_mesh_opts())

    SquidMesh.execute_next(opts)
  end

  @spec squid_mesh_opts() :: keyword()
  def squid_mesh_opts do
    [
      journal_storage:
        {Jido.Storage.File,
         path:
           Application.get_env(:the_beacon, :squid_mesh_journal_path, "tmp/squid_mesh_journal")}
    ]
  end
end
