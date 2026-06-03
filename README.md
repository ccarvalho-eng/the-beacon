# The Beacon

The Beacon is a plain OTP monitoring app that replaces the private
`ops-notifications` GitHub Actions loop with a Squid Mesh workflow.

V1 focuses on Elixir ecosystem security advisories:

- OSV package watchlist
- ERLEF CNA CVE sitemap
- GitHub Security Advisories for the Erlang ecosystem
- webhook notification delivery
- file-backed seen-state tracking

Only successfully delivered advisories are marked seen.

## Runtime

The application keeps the runtime small:

```text
OTP scheduler
  -> Squid Mesh security_check workflow
  -> security advisory monitor
  -> webhook delivery
  -> file-backed seen state
```

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
  squid_mesh_journal_path: "tmp/squid_mesh_journal"
```

Then start the OTP app:

```sh
mix run --no-halt
```

For tests and local module checks, runtime children stay disabled by default.

## ops-notifications Mapping

| ops-notifications | The Beacon |
| --- | --- |
| GitHub Actions schedule | `TheBeacon.Scheduler` |
| workflow shell/Python steps | Squid Mesh workflow step |
| committed `state/elixir-osv-seen.txt` | file-backed seen state |
| `curl`/`jq` webhook post | `SquidMesh.Tools.HTTP` |
| `DISCORD_WEBHOOK_SECURITY` | `BEACON_WEBHOOKS` |
