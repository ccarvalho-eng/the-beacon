# The Beacon

The Beacon is a plain OTP monitoring app built around a Squid Mesh workflow.

V1 focuses on Elixir ecosystem security advisories:

- OSV Hex ecosystem export
- ERLEF CNA CVE sitemap
- GitHub Security Advisories for the Erlang ecosystem
- webhook notification delivery
- file-backed seen-state tracking

Only successfully delivered advisories are marked seen.

## Runtime

The application keeps the runtime small:

```text
Bedrock JobQueue schedule job
  -> Bedrock JobQueue Squid Mesh payload job
  -> Squid Mesh security_check workflow
  -> security advisory monitor
  -> webhook delivery
  -> file-backed seen state
```

Bedrock JobQueue owns delayed visibility, job leases, retries, and worker
recovery. Squid Mesh owns workflow execution state and step history.

No Phoenix app, dashboard, or GitHub repository commits are required.

## Configuration

```sh
export BEACON_WEBHOOKS='["https://discord.com/api/webhooks/..."]'
export BEACON_SECURITY_CRON='*/15 * * * *'
export BEACON_SECURITY_STATE_FILE='state/security-seen.txt'
```

## Running

Enable the runtime children in application config:

```elixir
config :the_beacon,
  start_runtime: true,
  job_queue_id: "security",
  squid_mesh_journal_path: "tmp/squid_mesh_journal"
```

Then start the OTP app:

```sh
mix run --no-halt
```

For tests and local module checks, runtime children stay disabled by default.
