defmodule TheBeacon.SecurityMonitorTest do
  use ExUnit.Case, async: true

  alias Squidie.Tools.Result
  alias TheBeacon.Monitors.Security

  defmodule FakeHTTP do
    @behaviour Squidie.Tools.Adapter

    @impl true
    def invoke(%{method: :get, url: "https://osv.test/Hex/all.zip"} = request, _context, _opts) do
      send(self(), {:osv_request, request})

      {:ok,
       %Result{
         adapter: __MODULE__,
         payload: %{
           status: 200,
           body:
             zip([
               {"OSV-2026-1.json",
                %{
                  "id" => "OSV-2026-1",
                  "summary" => "phoenix issue",
                  "aliases" => ["CVE-2026-0001"]
                }}
             ])
         }
       }}
    end

    def invoke(%{method: :get, url: "https://osv.test/Hex/unzipped"} = request, _context, _opts) do
      send(self(), {:osv_request, request})

      {:ok,
       %Result{
         adapter: __MODULE__,
         payload: %{
           status: 200,
           body:
             zip_entries([
               {"OSV-2026-2.json",
                %{
                  "id" => "OSV-2026-2",
                  "summary" => "decoded archive issue",
                  "aliases" => ["CVE-2026-0003"]
                }}
             ])
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

    defp zip(entries) do
      {:ok, {_name, archive}} = :zip.create(~c"osv.zip", files(entries), [:memory])
      archive
    end

    defp zip_entries(entries) do
      {:ok, files} = :zip.unzip(zip(entries), [:memory])
      files
    end

    defp files(entries) do
      Enum.map(entries, fn {path, contents} ->
        {String.to_charlist(path), Jason.encode!(contents)}
      end)
    end
  end

  test "collects OSV, ERLEF CNA, and GitHub advisory events" do
    assert {:ok, events} =
             Security.check(
               http_adapter: FakeHTTP,
               osv_url: "https://osv.test/Hex/all.zip",
               erlef_sitemap_url: "https://cna.erlef.org/sitemap.xml",
               github_advisories_url: "https://api.github.test/advisories"
             )

    assert_receive {:osv_request, %{method: :get, url: "https://osv.test/Hex/all.zip"}}

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

  test "collects OSV events when HTTP returns decoded zip entries" do
    assert {:ok, events} =
             Security.check(
               http_adapter: FakeHTTP,
               osv_url: "https://osv.test/Hex/unzipped",
               erlef_sitemap_url: "https://cna.erlef.org/sitemap.xml",
               github_advisories_url: "https://api.github.test/advisories"
             )

    assert_receive {:osv_request, %{method: :get, url: "https://osv.test/Hex/unzipped"}}

    assert Enum.map(events, & &1.id) == [
             "OSV-2026-2",
             "CVE-2026-0002",
             "GHSA-2026-1"
           ]
  end
end
