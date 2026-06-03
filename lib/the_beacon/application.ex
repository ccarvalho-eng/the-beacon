defmodule TheBeacon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:the_beacon, :start_runtime, false) do
        [
          TheBeacon.Scheduler,
          TheBeacon.Worker
        ]
      else
        []
      end

    opts = [strategy: :one_for_one, name: TheBeacon.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
