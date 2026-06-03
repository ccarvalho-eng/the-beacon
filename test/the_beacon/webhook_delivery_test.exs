defmodule TheBeacon.WebhookDeliveryTest do
  use ExUnit.Case, async: true

  alias SquidMesh.Tools.Result
  alias TheBeacon.Event
  alias TheBeacon.Notifications.WebhookDelivery

  defmodule FakeHTTP do
    @behaviour SquidMesh.Tools.Adapter

    @impl true
    def invoke(%{method: :post, url: url, json: %{content: content}} = request, _context, _opts) do
      send(self(), {:webhook_request, url, content, request})

      {:ok,
       %Result{
         adapter: __MODULE__,
         payload: %{status: 204, body: ""}
       }}
    end
  end

  test "posts one security notification message to every configured webhook" do
    event = %Event{
      id: "GHSA-2026-1",
      source: "GitHub Advisory Database",
      title: "github issue",
      url: "https://github.com/advisories/GHSA-2026-1",
      details: "CVE-2026-0001"
    }

    assert :ok =
             WebhookDelivery.deliver([event],
               http_adapter: FakeHTTP,
               webhooks: ["https://discord.test/hook", "https://slack.test/hook"]
             )

    assert_receive {:webhook_request, "https://discord.test/hook", content, _request}
    assert content =~ "New Elixir ecosystem vulnerability findings"
    assert content =~ "GitHub Advisory Database: GHSA-2026-1"
    assert content =~ "github issue"
    assert content =~ "https://github.com/advisories/GHSA-2026-1"

    assert_receive {:webhook_request, "https://slack.test/hook", ^content, _request}
  end

  test "splits large security notifications into webhook-sized messages" do
    events =
      for index <- 1..20 do
        %Event{
          id: "GHSA-2026-#{index}",
          source: "GitHub Advisory Database",
          title: String.duplicate("large advisory title ", 12),
          url: "https://github.com/advisories/GHSA-2026-#{index}",
          details: "CVE-2026-#{index}"
        }
      end

    assert :ok =
             WebhookDelivery.deliver(events,
               http_adapter: FakeHTTP,
               webhooks: ["https://discord.test/hook"]
             )

    contents = received_webhook_contents()

    assert length(contents) > 1
    assert Enum.all?(contents, &(String.length(&1) <= 2_000))

    for event <- events do
      assert Enum.any?(contents, &String.contains?(&1, event.id))
    end
  end

  test "trims a single oversized advisory before posting" do
    event = %Event{
      id: "GHSA-2026-oversized",
      source: "GitHub Advisory Database",
      title: String.duplicate("oversized advisory title ", 200),
      url: "https://github.com/advisories/GHSA-2026-oversized",
      details: String.duplicate("CVE-2026-oversized ", 200)
    }

    assert :ok =
             WebhookDelivery.deliver([event],
               http_adapter: FakeHTTP,
               webhooks: ["https://discord.test/hook"]
             )

    assert_receive {:webhook_request, "https://discord.test/hook", content, _request}
    assert String.length(content) <= 2_000
    assert content =~ "GHSA-2026-oversized"
    assert content =~ "..."
  end

  test "fails delivery when no webhook is configured" do
    event = %Event{
      id: "GHSA-2026-1",
      source: "GitHub Advisory Database",
      title: "github issue",
      url: "https://github.com/advisories/GHSA-2026-1"
    }

    assert {:error, :no_webhooks_configured} =
             WebhookDelivery.deliver([event], http_adapter: FakeHTTP, webhooks: [])
  end

  defp received_webhook_contents do
    self()
    |> Process.info(:messages)
    |> elem(1)
    |> Enum.flat_map(fn
      {:webhook_request, _url, content, _request} -> [content]
      _message -> []
    end)
  end
end
