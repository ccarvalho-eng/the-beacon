defmodule TheBeacon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    TheBeacon.Runtime.configure_squid_mesh!()

    opts = [strategy: :one_for_one, name: TheBeacon.Supervisor]
    Supervisor.start_link(runtime_children(), opts)
  end

  @spec runtime_children() :: [Supervisor.child_spec()]
  def runtime_children do
    [
      {TheBeacon.BedrockCluster, []},
      {TheBeacon.JobQueue,
       concurrency: job_queue_concurrency(), batch_size: job_queue_batch_size()},
      TheBeacon.ScheduleBootstrap
    ]
  end

  defp job_queue_concurrency do
    Application.get_env(:the_beacon, :job_queue_concurrency, System.schedulers_online())
  end

  defp job_queue_batch_size do
    Application.get_env(:the_beacon, :job_queue_batch_size, 10)
  end
end
