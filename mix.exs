defmodule TheBeacon.MixProject do
  use Mix.Project

  def project do
    [
      app: :the_beacon,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [extra_applications: [:logger]]
    |> Keyword.merge(application_mod())
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bedrock, "~> 0.4.0"},
      {:bedrock_job_queue, "~> 0.1.0"},
      {:jason, "~> 1.4"},
      {:squid_mesh, "~> 0.1.1"}
    ]
  end

  defp application_mod do
    if Mix.env() == :test do
      []
    else
      [mod: {TheBeacon.Application, []}]
    end
  end

  defp aliases do
    [
      precommit: ["format --check-formatted", "compile --warnings-as-errors", "test"]
    ]
  end
end
