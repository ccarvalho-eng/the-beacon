defmodule TheBeacon.SecurityMonitorTest do
  use ExUnit.Case, async: true

  alias SquidMesh.Tools.Result
  alias TheBeacon.Monitors.Security

  defmodule FakeHTTP do
    @behaviour SquidMesh.Tools.Adapter

    @impl true
    def invoke(
          %{method: :post, url: "https://api.osv.dev/v1/querybatch"} = request,
          _context,
          _opts
        ) do
      send(self(), {:osv_request, request})

      {:ok,
       %Result{
         adapter: __MODULE__,
         payload: %{
           status: 200,
           body: %{
             "results" => [
               %{
                 "vulns" => [
                   %{
                     "id" => "OSV-2026-1",
                     "summary" => "phoenix issue",
                     "aliases" => ["CVE-2026-0001"]
                   }
                 ]
               }
             ]
           }
         }
       }}
    end

    def invoke(%{method: :get, url: "https://cna.erlef.org/sitemap.xml"}, _context, _opts) do
      {:ok,
       %Result{
         adapter: __MODULE__,
         payload: %{
           status: 200,
           body: """
           <urlset>
             <url><loc>https://cna.erlef.org/cves/CVE-2026-0002.html</loc></url>
           </urlset>
           """
         }
       }}
    end

    def invoke(%{method: :get, url: "https://api.github.test/advisories"}, _context, _opts) do
      {:ok,
       %Result{
         adapter: __MODULE__,
         payload: %{
           status: 200,
           body: [
             %{
               "ghsa_id" => "GHSA-2026-1",
               "summary" => "github issue",
               "html_url" => "https://github.com/advisories/GHSA-2026-1"
             }
           ]
         }
       }}
    end
  end

  test "collects OSV, ERLEF CNA, and GitHub advisory events" do
    assert {:ok, events} =
             Security.check(
               http_adapter: FakeHTTP,
               osv_watchlist: [%{ecosystem: "Hex", name: "phoenix"}],
               erlef_sitemap_url: "https://cna.erlef.org/sitemap.xml",
               github_advisories_url: "https://api.github.test/advisories"
             )

    assert_receive {:osv_request,
                    %{
                      json: %{
                        queries: [
                          %{package: %{ecosystem: "Hex", name: "phoenix"}}
                        ]
                      }
                    }}

    assert Enum.map(events, & &1.id) == [
             "OSV-2026-1",
             "CVE-2026-0002",
             "GHSA-2026-1"
           ]

    assert Enum.map(events, & &1.source) == [
             "OSV",
             "ERLEF CNA",
             "GitHub Advisory Database"
           ]
  end
end
