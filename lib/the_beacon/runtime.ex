defmodule TheBeacon.Runtime do
  @moduledoc """
  Host-owned boundary for starting and draining Beacon Squid Mesh work.
  """

  alias SquidMesh.Executor.Payload
  alias SquidMesh.Runtime.Runner

  @workflow TheBeacon.Workflows.SecurityCheck
  @trigger :scheduled_security_check

  @spec start_security_check(keyword()) :: :ok | {:error, term()}
  def start_security_check(opts \\ []) do
    payload =
      Payload.cron(@workflow, @trigger,
        signal_id: Keyword.get(opts, :signal_id, default_signal_id()),
        intended_window: Keyword.get(opts, :intended_window, default_window())
      )

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

  defp default_signal_id do
    "security-check:" <> DateTime.to_iso8601(DateTime.utc_now())
  end

  defp default_window do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    %{"start_at" => now, "end_at" => now}
  end
end
