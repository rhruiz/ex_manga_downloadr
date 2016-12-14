defmodule ExMangaDownloadr do
  require Logger

  @user_agent   Application.get_env(:ex_manga_downloadr, :user_agent)
  @http_timeout 60_000

  # will retry failed fetches over 50 times, sleeping 1 second between each retry
  @max_retries  50
  @time_to_wait_to_fetch_again 1_000

  @doc """
  All HTTPoison.Response bodies should go through this gunzip process
  """
  def gunzip(body, headers) do
    if Enum.member?(headers, {"Content-Encoding", "gzip"}) do
      :zlib.gunzip(body)
    else
      body
    end
  end

  @doc """
  All HTTPoison requests should use this set of options
  """
  def http_headers do
    [{"User-Agent", @user_agent}, {"Accept-encoding", "gzip"}, {"Connection", "keep-alive"}]
  end

  def http_options do
    [timeout: @http_timeout]
  end

  def retryable_http_get(url, retries \\ @max_retries)
  def retryable_http_get(url, 0), do: raise "Failed to fetch from #{url} after #{@max_retries} retries."
  def retryable_http_get(url, retries) when retries > 0 do
    try do
      cache_path = "/tmp/ex_manga_downloadr_cache/#{cache_filename(url)}"
      response = if System.get_env("CACHE_HTTP") && File.exists?(cache_path) do
        {:ok, body} = File.read(cache_path)
        %HTTPoison.Response{ body: body, headers: [ "Content-Encoding": "" ], status_code: 200}
      else
        HTTPoison.get!(url, http_headers, http_options)
      end
      case response do
        %HTTPoison.Response{ body: _, headers: _, status_code: status } when status > 499 ->
          raise %HTTPoison.Error{reason: "req_timedout"}
        %HTTPoison.Response{ body: _, headers: headers, status_code: status} when status > 300 and status < 400 ->
          retryable_http_get(headers["Location"], retries)
        %HTTPoison.Response{ body: body, headers: headers, status_code: _ } ->
          if System.get_env("CACHE_HTTP") && !File.exists?(cache_path) do
            File.write!(cache_path, gunzip(body, headers))
          end
          response
        %HTTPoison.Error{} ->
            :timer.sleep(@time_to_wait_to_fetch_again)
            retryable_http_get(url, retries - 1)
          end
    rescue
      _ in HTTPoison.Error ->
	      :timer.sleep(@time_to_wait_to_fetch_again)
	      retryable_http_get(url, retries - 1)
    end
  end

  defp cache_filename(url) do
    url
  end

  defmacro fetch(link, do: expression) do
    quote do
      case ExMangaDownloadr.retryable_http_get(unquote(link)) do
        %HTTPoison.Response{ body: body, headers: headers, status_code: 200 } ->
          { :ok, body |> ExMangaDownloadr.gunzip(headers) |> unquote(expression) }
      end
    end
  end

  ## Phoenix like "use ExMangaDownloadr, :mangareader" for aliasing

  def mangareader do
    quote do
      alias ExMangaDownloadr.MangaReader.IndexPage
      alias ExMangaDownloadr.MangaReader.ChapterPage
      alias ExMangaDownloadr.MangaReader.Page
    end
  end

  def mangafox do
    quote do
      alias ExMangaDownloadr.Mangafox.IndexPage
      alias ExMangaDownloadr.Mangafox.ChapterPage
      alias ExMangaDownloadr.Mangafox.Page
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
