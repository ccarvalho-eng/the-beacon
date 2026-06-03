defmodule TheBeacon.Monitors.Security do
  @moduledoc """
  Security advisory monitor for Elixir ecosystem sources.
  """

  @behaviour TheBeacon.Monitor

  alias SquidMesh.Tools
  alias TheBeacon.Event

  @default_osv_url "https://osv-vulnerabilities.storage.googleapis.com/Hex/all.zip"
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
      method: :get,
      url: opts.osv_url
    }

    with {:ok, result} <- Tools.invoke(opts.http_adapter, request, %{}),
         {:ok, vulnerabilities} <- decode_osv_archive(body(result)) do
      events =
        vulnerabilities
        |> Enum.map(&osv_event/1)
        |> Enum.sort_by(& &1.id)

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

  defp osv_event(vuln) do
    aliases = Map.get(vuln, "aliases", [])
    details = aliases |> Enum.join(", ") |> blank_to_nil()

    %Event{
      id: Map.fetch!(vuln, "id"),
      source: "OSV",
      title: Map.get(vuln, "summary") || Map.get(vuln, "details") || Map.fetch!(vuln, "id"),
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
      erlef_sitemap_url: Map.get(opts, :erlef_sitemap_url, @default_erlef_url),
      github_advisories_url: Map.get(opts, :github_advisories_url, @default_github_url)
    }
  end

  defp decode_osv_archive(archive) do
    with {:ok, files} <- unzip(archive) do
      files
      |> Enum.filter(fn {path, _contents} -> Path.extname(to_string(path)) == ".json" end)
      |> Enum.map(fn {_path, contents} -> Jason.decode!(contents) end)
      |> then(&{:ok, &1})
    end
  end

  defp unzip(archive) when is_binary(archive) do
    case :zip.unzip(archive, [:memory]) do
      {:ok, files} -> {:ok, files}
      {:error, reason} -> {:error, {:invalid_osv_archive, reason}}
    end
  end

  defp body(%{payload: %{body: body}}), do: body
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
