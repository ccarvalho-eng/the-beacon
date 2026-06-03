defmodule TheBeacon.Monitors.Security do
  @moduledoc """
  Security advisory monitor based on the original ops-notifications workflow.
  """

  @behaviour TheBeacon.Monitor

  alias SquidMesh.Tools
  alias TheBeacon.Event

  @default_osv_url "https://api.osv.dev/v1/querybatch"
  @default_erlef_url "https://cna.erlef.org/sitemap.xml"
  @default_github_url "https://api.github.com/advisories?ecosystem=erlang&per_page=30&sort=updated&direction=desc"

  @impl true
  def check(opts) do
    opts = normalize_opts(opts)

    with {:ok, osv_events} <- fetch_osv(opts),
         {:ok, erlef_events} <- fetch_erlef(opts),
         {:ok, github_events} <- fetch_github(opts) do
      {:ok, osv_events ++ erlef_events ++ github_events}
    end
  end

  defp fetch_osv(opts) do
    request = %{
      method: :post,
      url: opts.osv_url,
      json: %{
        queries:
          Enum.map(opts.osv_watchlist, fn package ->
            %{package: %{ecosystem: package.ecosystem, name: package.name}}
          end)
      }
    }

    with {:ok, result} <- Tools.invoke(opts.http_adapter, request, %{}) do
      results = body(result) |> Map.get("results", [])

      events =
        results
        |> Enum.zip(opts.osv_watchlist)
        |> Enum.flat_map(fn {result, package} ->
          result
          |> Map.get("vulns", [])
          |> Enum.map(&osv_event(package, &1))
        end)

      {:ok, events}
    end
  end

  defp fetch_erlef(opts) do
    with {:ok, result} <-
           Tools.invoke(opts.http_adapter, %{method: :get, url: opts.erlef_sitemap_url}, %{}) do
      events =
        result
        |> body()
        |> to_string()
        |> then(&Regex.scan(~r/CVE-\d+-\d+/, &1))
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map(&erlef_event/1)

      {:ok, events}
    end
  end

  defp fetch_github(opts) do
    request = %{
      method: :get,
      url: opts.github_advisories_url,
      headers: [{"X-GitHub-Api-Version", "2022-11-28"}]
    }

    with {:ok, result} <- Tools.invoke(opts.http_adapter, request, %{}) do
      events =
        result
        |> body()
        |> Enum.map(&github_event/1)

      {:ok, events}
    end
  end

  defp osv_event(package, vuln) do
    aliases = Map.get(vuln, "aliases", [])
    details = aliases |> Enum.join(", ") |> blank_to_nil()

    %Event{
      id: Map.fetch!(vuln, "id"),
      source: "OSV",
      title: Map.get(vuln, "summary") || Map.get(vuln, "details") || package.name,
      url: "https://osv.dev/vulnerability/#{Map.fetch!(vuln, "id")}",
      details: details
    }
  end

  defp erlef_event(cve) do
    %Event{
      id: cve,
      source: "ERLEF CNA",
      title: "ERLEF CNA advisory published",
      url: "https://cna.erlef.org/cves/#{cve}.html"
    }
  end

  defp github_event(advisory) do
    %Event{
      id: Map.fetch!(advisory, "ghsa_id"),
      source: "GitHub Advisory Database",
      title: Map.get(advisory, "summary") || Map.fetch!(advisory, "ghsa_id"),
      url:
        Map.get(advisory, "html_url") ||
          "https://github.com/advisories/#{Map.fetch!(advisory, "ghsa_id")}"
    }
  end

  defp normalize_opts(opts) do
    opts = Map.new(opts)

    %{
      http_adapter: Map.get(opts, :http_adapter, SquidMesh.Tools.HTTP),
      osv_url: Map.get(opts, :osv_url, @default_osv_url),
      osv_watchlist: normalize_watchlist(Map.get(opts, :osv_watchlist, default_watchlist())),
      erlef_sitemap_url: Map.get(opts, :erlef_sitemap_url, @default_erlef_url),
      github_advisories_url: Map.get(opts, :github_advisories_url, @default_github_url)
    }
  end

  defp normalize_watchlist(packages) do
    Enum.map(packages, fn package ->
      package
      |> Map.new()
      |> then(&%{ecosystem: Map.fetch!(&1, :ecosystem), name: Map.fetch!(&1, :name)})
    end)
  end

  defp default_watchlist do
    [
      %{ecosystem: "Hex", name: "phoenix"},
      %{ecosystem: "Hex", name: "plug"},
      %{ecosystem: "Hex", name: "cowboy"},
      %{ecosystem: "Hex", name: "bandit"},
      %{ecosystem: "Hex", name: "ecto"},
      %{ecosystem: "Hex", name: "oban"},
      %{ecosystem: "Hex", name: "jido"},
      %{ecosystem: "Hex", name: "bedrock"}
    ]
  end

  defp body(%{payload: %{body: body}}), do: body
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
