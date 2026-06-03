defmodule TheBeacon.Workflows.SecurityCheck do
  @moduledoc """
  Squid Mesh workflow for scheduled security checks.
  """

  use SquidMesh.Workflow

  workflow do
    trigger :security_check do
      manual()

      payload do
        field :state_file, :string, default: "state/security-seen.txt"
        field :webhooks, :list, default: []
      end
    end

    trigger :scheduled_security_check do
      cron "*/15 * * * *", timezone: "Etc/UTC", idempotency: :return_existing_run

      payload do
        field :state_file, :string, default: "state/security-seen.txt"
        field :webhooks, :list, default: []
      end
    end

    step :run_security_check, TheBeacon.Steps.RunSecurityCheck,
      retry: [max_attempts: 3, backoff: [type: :exponential, min: 1_000, max: 30_000]]

    transition :run_security_check, on: :ok, to: :complete
  end
end
