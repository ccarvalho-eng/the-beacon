# The Beacon

The Beacon is a plain OTP app for scheduled monitoring and notifications.

The first workflow monitors Elixir ecosystem security advisories and delivers
notifications:

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
     -> fetch_security_events
     -> filter_seen_events
     -> deliver_security_notifications
     -> mark_seen_events
```

Bedrock JobQueue owns delayed visibility, job leases, retries, and worker
recovery. Squid Mesh owns workflow execution state and step history.

No Phoenix app, dashboard, or GitHub repository commits are required.

## Configuration

```sh
export BEACON_WEBHOOKS='["https://discord.com/api/webhooks/..."]'
```

For local development, keep secrets in `.env.local` and source it before
starting the app:

```sh
source .env.local
```

Do not commit `.env.local` or paste webhook URLs into logs, issues, PRs, or
screenshots.

### Discord Webhook Setup

Use a private Discord server or private channel for Beacon notifications:

1. In Discord, create a server with **Add a Server** and **Create My Own**.
2. Create a private text channel for Beacon notifications.
3. Open **Server Settings** or the channel settings, then **Integrations** and
   **Webhooks**.
4. Create a webhook, choose the Beacon notification channel, and copy the
   webhook URL.
5. Store the URL as a JSON list:

   ```sh
   export BEACON_WEBHOOKS='["https://discord.com/api/webhooks/..."]'
   ```

Discord’s own docs cover the moving UI details:

- [Create a server](https://support.discord.com/hc/en-us/articles/204849977-How-do-I-create-a-server)
- [Intro to webhooks](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks)
- [Server integrations](https://support.discord.com/hc/en-us/articles/360045093012-Server-Integrations-Page)

The security check schedule is declared by the Squid Mesh workflow:

```elixir
trigger :scheduled_security_check do
  cron "*/15 * * * *", timezone: "Etc/UTC", idempotency: :return_existing_run
end
```

That workflow declaration is the schedule source of truth. Do not also pass a
cron through environment config.

The seen-state file is workflow input. The default payload value is
`state/security-seen.txt`; manual or host-delivered payloads can pass a
different `state_file` when they intentionally need one.

## Running

Start the OTP app in non-interactive service mode:

```sh
elixir --sname beacon -S mix run --no-halt
```

This keeps the VM running and does not open an IEx prompt.

Do not use plain `mix run` for the scheduler process. It boots the application,
prints startup logs, and exits when the Mix task finishes.

Also do not use `elixir --sname beacon -S mix` when you want an interactive
shell. That starts Mix under a named node, but it does not open IEx and it does
not keep the VM alive.

For an interactive session, start IEx with the same node-name requirement and
leave it running:

```sh
iex --sname beacon -S mix
```

From IEx, trigger the security workflow manually:

```elixir
{:ok, run} =
  SquidMesh.start(
    TheBeacon.Workflows.SecurityCheck,
    :security_check,
    %{state_file: "state/security-seen.txt"}
  )

SquidMesh.execute_next(owner_id: "manual-security-check")
```

Run `SquidMesh.execute_next/1` again until it returns `{:ok, :none}`.

The application starts the Bedrock cluster, Bedrock JobQueue, and schedule
bootstrap by default. The bootstrap seeds the next security schedule job from
the workflow cron definition.

Bedrock expects the Erlang VM to run as a named node. Use `--sname` for local
single-node development. Without `--sname` or `--name`, Bedrock emits:

```text
Bedrock: This node is not part of a cluster (use the "--name" or "--sname" option when starting the Erlang VM)
```

With `--sname`, local development may still emit:

```text
Bedrock: Creating a default single-node configuration
```

That warning is expected for local single-node runs unless a custom Bedrock
cluster configuration is provided.

You may also see startup logs like:

```text
Bedrock [Elixir.TheBeacon.BedrockCluster]: Leader waiting for TSL restoration from Raft before starting director
```

That is normal Bedrock startup output. The important distinction is whether the
VM stays alive: use `run --no-halt` for service mode or `iex` for interactive
mode.

## Manual Test

Start an interactive local node:

```sh
source .env.local
iex --sname beacon -S mix
```

Then enqueue a due security schedule job:

```elixir
scheduled_for = DateTime.add(DateTime.utc_now(), -1, :second)

TheBeacon.JobQueue.enqueue(
  TheBeacon.JobQueue.queue_id(),
  "beacon:schedule:security",
  %{scheduled_for: DateTime.to_iso8601(scheduled_for)},
  at: scheduled_for,
  id: "manual-security-schedule:" <> DateTime.to_iso8601(scheduled_for)
)
```

Useful checks while it runs:

```elixir
TheBeacon.JobQueue.stats(TheBeacon.JobQueue.queue_id())
SquidMesh.list_runs([], TheBeacon.Runtime.squid_mesh_opts())
File.exists?("state/security-seen.txt")
```

When new advisories are delivered, the workflow should log delivery, mark those
events seen, and complete. The seen-state file is local runtime state and is
ignored by git.
