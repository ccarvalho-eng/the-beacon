defmodule TheBeacon.Workflows.SecurityCheck do
  @moduledoc """
  Squid Mesh workflow for scheduled security checks.
  """

  use SquidMesh.Workflow

  alias TheBeacon.Steps.{
    DeliverSecurityNotifications,
    FetchSecurityEvents,
    FilterSeenEvents,
    MarkSeenEvents
  }

  workflow do
    trigger :security_check do
      manual()

      payload do
        field :state_file, :string, default: "state/security-seen.txt"
      end
    end

    trigger :scheduled_security_check do
      cron "*/15 * * * *", timezone: "Etc/UTC", idempotency: :return_existing_run

      payload do
        field :state_file, :string, default: "state/security-seen.txt"
      end
    end

    step :log_security_check_started, :log,
      message: "Security check started",
      level: :info

    step :fetch_security_events, FetchSecurityEvents,
      output: :security_events,
      retry: [max_attempts: 3, backoff: [type: :exponential, min: 1_000, max: 30_000]]

    step :filter_seen_events, FilterSeenEvents,
      input: [
        state_file: [:state_file],
        events: [:security_events, :events]
      ],
      output: :unseen_security_events

    step :deliver_security_notifications, DeliverSecurityNotifications,
      input: [
        events: [:unseen_security_events, :events],
        checked_count: [:unseen_security_events, :checked_count],
        new_count: [:unseen_security_events, :new_count]
      ],
      output: :delivered_security_events,
      irreversible: true,
      retry: [max_attempts: 3, backoff: [type: :exponential, min: 1_000, max: 30_000]]

    step :mark_seen_events, MarkSeenEvents,
      input: [
        state_file: [:state_file],
        events: [:delivered_security_events, :events],
        checked_count: [:delivered_security_events, :checked_count],
        new_count: [:delivered_security_events, :new_count],
        delivered_count: [:delivered_security_events, :delivered_count]
      ],
      output: :security_check

    step :log_security_check_completed, :log,
      message: "Security check completed",
      level: :info

    transition :log_security_check_started, on: :ok, to: :fetch_security_events
    transition :fetch_security_events, on: :ok, to: :filter_seen_events
    transition :filter_seen_events, on: :ok, to: :deliver_security_notifications
    transition :deliver_security_notifications, on: :ok, to: :mark_seen_events
    transition :mark_seen_events, on: :ok, to: :log_security_check_completed
    transition :log_security_check_completed, on: :ok, to: :complete
  end
end
