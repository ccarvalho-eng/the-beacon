defmodule TheBeacon.SecuritySmoke do
  @moduledoc false

  @schedule_topic "beacon:schedule:security"
  @default_timeout_ms 60_000
  @poll_interval_ms 500
  @default_state_file "state/security-seen.txt"

  def main(argv) do
    case parse(argv) do
      {:ok, opts} ->
        run(opts)

      {:error, reason} ->
        IO.puts(:stderr, "security smoke failed: #{reason}")
        System.halt(2)

      :help ->
        usage()
    end
  end

  defp parse(argv) do
    argv = drop_mix_separator(argv)

    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [
          reset: :boolean,
          timeout: :integer,
          help: :boolean
        ]
      )

    cond do
      opts[:help] ->
        :help

      invalid != [] ->
        {:error, "invalid options: #{inspect(invalid)}"}

      args != [] ->
        {:error, "unexpected arguments: #{Enum.join(args, " ")}"}

      true ->
        {:ok,
         %{
           reset?: Keyword.get(opts, :reset, false),
           timeout_ms: Keyword.get(opts, :timeout, @default_timeout_ms)
         }}
    end
  end

  defp drop_mix_separator(["--" | argv]), do: argv
  defp drop_mix_separator(argv), do: argv

  defp usage do
    IO.puts("""
    Usage:
      mix run --no-start scripts/security_smoke.exs -- [--reset] [--timeout 60000]

    Options:
      --reset          Remove local tmp runtime state and the default seen-state file before boot.
      --timeout MS     Maximum time to wait for the smoke run. Defaults to 60000.

    Notes:
      Run with --no-start so --reset happens before Bedrock and Squid Mesh boot.
      The script prints whether webhooks are configured, but never prints webhook values.
    """)
  end

  defp run(opts) do
    maybe_reset!(opts.reset?)
    print_webhook_status()

    {:ok, _started} = Application.ensure_all_started(:the_beacon)

    before_runs = current_runs!()
    before_run_ids = MapSet.new(Enum.map(before_runs, & &1.run_id))

    IO.puts("queue before enqueue: #{inspect(queue_stats())}")

    scheduled_for = DateTime.add(DateTime.utc_now(), -1, :second)
    enqueue_due_schedule!(scheduled_for)

    IO.puts("enqueued due #{@schedule_topic} job for #{DateTime.to_iso8601(scheduled_for)}")

    deadline = System.monotonic_time(:millisecond) + opts.timeout_ms
    run = wait_for_new_run!(before_run_ids, deadline)

    IO.puts("started Squid Mesh run #{run.run_id}")

    final_run = wait_for_terminal_run!(run.run_id, deadline)
    print_run_summary(final_run)

    if final_run.terminal_status == :completed do
      IO.puts("security smoke passed")
    else
      IO.puts(:stderr, "security smoke failed")
      System.halt(1)
    end
  end

  defp maybe_reset!(false), do: :ok

  defp maybe_reset!(true) do
    File.rm_rf!("tmp")
    File.rm_rf!(@default_state_file)
    IO.puts("removed local tmp runtime state and #{@default_state_file}")
  end

  defp print_webhook_status do
    configured? = TheBeacon.Config.webhooks() != []
    IO.puts("webhooks configured?: #{configured?}")

    unless configured? do
      IO.puts("delivery will fail if the security check finds new events")
    end
  end

  defp enqueue_due_schedule!(scheduled_for) do
    payload = %{scheduled_for: DateTime.to_iso8601(scheduled_for)}
    id = "smoke-security-schedule:" <> DateTime.to_iso8601(scheduled_for)

    case TheBeacon.JobQueue.enqueue(TheBeacon.JobQueue.queue_id(), @schedule_topic, payload,
           at: scheduled_for,
           id: id
         ) do
      {:ok, _item} -> :ok
      {:error, reason} -> fail!("could not enqueue schedule job: #{safe_inspect(reason)}")
      other -> fail!("unexpected enqueue result: #{safe_inspect(other)}")
    end
  end

  defp wait_for_new_run!(before_run_ids, deadline) do
    wait_until!(deadline, "new Squid Mesh run", fn ->
      runs = current_runs!()

      Enum.find(runs, fn run ->
        not MapSet.member?(before_run_ids, run.run_id)
      end)
    end)
  end

  defp wait_for_terminal_run!(run_id, deadline) do
    wait_until!(deadline, "terminal Squid Mesh run", fn ->
      drain_once!()

      runs = current_runs!()
      run = Enum.find(runs, &(&1.run_id == run_id))

      cond do
        run == nil -> nil
        run.terminal? -> run
        true -> nil
      end
    end)
  end

  defp wait_until!(deadline, description, fun) do
    case fun.() do
      nil ->
        if System.monotonic_time(:millisecond) >= deadline do
          fail!("timed out waiting for #{description}; queue: #{inspect(queue_stats())}")
        else
          Process.sleep(@poll_interval_ms)
          wait_until!(deadline, description, fun)
        end

      result ->
        result
    end
  end

  defp drain_once! do
    opts = [
      owner_id: "the-beacon-security-smoke",
      heartbeat_interval_ms: 1_000
    ]

    case TheBeacon.Runtime.drain_once(opts) do
      {:ok, _result} -> :ok
      {:error, reason} -> fail!("Squid Mesh drain failed: #{safe_inspect(reason)}")
    end
  end

  defp current_runs! do
    case SquidMesh.list_runs([], TheBeacon.Runtime.squid_mesh_opts()) do
      {:ok, runs} -> runs
      {:error, reason} -> fail!("could not list Squid Mesh runs: #{safe_inspect(reason)}")
    end
  end

  defp print_run_summary(run) do
    IO.puts("queue after run: #{inspect(queue_stats())}")

    summary = %{
      run_id: run.run_id,
      workflow: run.workflow,
      status: run.status,
      terminal?: run.terminal?,
      terminal_status: run.terminal_status,
      thread_revision: run.thread_revision,
      anomalies: redact(run.anomalies)
    }

    IO.inspect(summary, label: "run")
    print_attempt_summary(run.run_id)
  end

  defp print_attempt_summary(run_id) do
    case SquidMesh.inspect_run(run_id, TheBeacon.Runtime.squid_mesh_opts()) do
      {:ok, snapshot} ->
        attempts = Enum.map(snapshot.attempts, &attempt_summary/1)
        IO.inspect(attempts, label: "attempts")

      {:error, reason} ->
        IO.puts(:stderr, "could not inspect run attempts: #{safe_inspect(reason)}")
    end
  end

  defp attempt_summary(attempt) do
    %{
      step: Map.get(attempt, :step) || Map.get(attempt, "step"),
      status: Map.get(attempt, :status) || Map.get(attempt, "status"),
      applied?: Map.get(attempt, :applied?) || Map.get(attempt, "applied?"),
      error: redact(Map.get(attempt, :error) || Map.get(attempt, "error"))
    }
  end

  defp queue_stats do
    TheBeacon.JobQueue.stats(TheBeacon.JobQueue.queue_id())
  end

  defp fail!(message) do
    IO.puts(:stderr, "security smoke failed: #{message}")
    System.halt(1)
  end

  defp safe_inspect(term) do
    redacted = redact(term)
    inspect(redacted, limit: 20, printable_limit: 1_000)
  end

  defp redact(term) when is_binary(term) do
    Regex.replace(
      ~r"https://(?:discord(?:app)?\.com|canary\.discord\.com)/api/webhooks/[^\s\"'<>]+",
      term,
      "[REDACTED_DISCORD_WEBHOOK]"
    )
  end

  defp redact(term) when is_list(term), do: Enum.map(term, &redact/1)

  defp redact(term) when is_map(term) do
    Map.new(term, fn {key, value} ->
      {key, redact(value)}
    end)
  end

  defp redact(term) when is_tuple(term) do
    list = Tuple.to_list(term)
    redacted = redact(list)
    List.to_tuple(redacted)
  end

  defp redact(term), do: term
end

TheBeacon.SecuritySmoke.main(System.argv())
