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

  test "posts one ops-notifications style message to every configured webhook" do
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
end
