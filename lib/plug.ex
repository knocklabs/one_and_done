defmodule OneAndDone.Plug do
  @moduledoc """
  Easy to use plug for idempoent requests.

  ## Getting started

  1. Add `:one_and_done` to your list of dependencies in `mix.exs`:

      ```elixir
      def deps do
        [
          {:one_and_done, "~> 0.1.0"}
        ]
      end
      ```

  2. Add the plug to your router:

      ```elixir
      pipeline :api do
        plug OneAndDone.Plug,
          # Required: must conform to OneAndDone.Cache (Nebulex.Cache works fine)
          cache: MyApp.Cache,

          # Optional: How long to keep entries, defaults to 86_400 (24 hours)
          ttl: 86_400,

          # Optional: Which methods to cache, defaults to ["POST", "PUT"]
          supported_methods: ["POST", "PUT"],

          # Optional: Function to generate the idempotency key for a given request.
          # By default, uses the value of the "Idempotency-Key" header.
          # Must return a binary or nil. If nil is returned, the request will not be cached.
          idempotency_key_fn: fn conn -> Plug.Conn.get_req_header(conn, "Some other header") |> List.first() end

          # Optional: Function to generate the cache key for a given request.
          # Given the idempotency key (returned from idempotency_key_fn), this function
          # should return a term that will be used as the cache key.
          # By default, it returns a tuple of the module name and the idempotency key.
          cache_key_fn: fn idempotency_key -> {__MODULE__, idempotency_key}
      end
      ```

      That's it! POST and PUT requests will now be cached by default for 24 hours.
  """

  @behaviour Plug

  alias OneAndDone.Response

  @supported_methods ["POST", "PUT"]
  @ttl :timer.hours(24)

  @impl Plug
  @spec init(cache: OneAndDone.Cache.t()) :: %{
          cache: any,
          cache_key_fn: any,
          idempotency_key_fn: any,
          supported_methods: any,
          ttl: any
        }
  def init(opts) do
    %{
      cache: Keyword.get(opts, :cache) || raise("Cache must be set"),
      ttl: Keyword.get(opts, :ttl, @ttl),
      supported_methods: Keyword.get(opts, :supported_methods, @supported_methods),
      idempotency_key_fn: Keyword.get(opts, :idempotency_key_fn, &idempotency_key_from_conn/1),
      cache_key_fn: Keyword.get(opts, :cache_key_fn, &build_cache_key/1)
    }
  end

  @impl Plug
  def call(conn, opts) do
    if is_idempotent?(conn, opts) do
      idempotency_key = opts.idempotency_key_fn.(conn)
      handle_idempotent_request(conn, idempotency_key, opts)
    else
      conn
    end
  end

  defp is_idempotent?(conn, opts) do
    Enum.any?(opts.supported_methods, &(&1 == conn.method))
  end

  # If we didn't get an idempotency key, move on
  defp handle_idempotent_request(conn, nil, _), do: conn

  defp handle_idempotent_request(conn, idempotency_key, opts) do
    case opts.cache.get(idempotency_key) do
      {:ok, cached_response} ->
        handle_cache_hit(conn, cached_response)

      # Cache miss passes through; we cache the response in the response callback
      _ ->
        Plug.Conn.register_before_send(conn, fn conn ->
          cache_response(conn, idempotency_key, opts)
        end)
    end
  end

  defp handle_cache_hit(conn, response) do
    conn =
      Enum.reduce(response.cookies, conn, fn {key, %{value: value}}, conn ->
        Plug.Conn.put_resp_cookie(conn, key, value)
      end)

    conn =
      Enum.reduce(response.headers, conn, fn {key, value}, conn ->
        Plug.Conn.put_resp_header(conn, key, value)
      end)

    Plug.Conn.send_resp(conn, response.status, response.body)
  end

  defp cache_response(conn, idempotency_key, opts) do
    response = Response.build_response(conn)
    opts.cache.put(idempotency_key, {:ok, response}, ttl: opts.ttl)

    conn
  end

  defp idempotency_key_from_conn(%Plug.Conn{} = conn) do
    conn
    |> Plug.Conn.get_req_header("idempotency-key")
    |> List.first()
  end

  defp build_cache_key(idempotency_key), do: {__MODULE__, idempotency_key}
end
