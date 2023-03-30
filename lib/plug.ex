defmodule OneAndDone.Plug do
  @moduledoc """
  Easy to use plug for idempoent requests.

  ## Getting started

  1. Add `:one_and_done` to your list of dependencies in `mix.exs`:

      ```elixir
      def deps do
        [
          {:one_and_done, "~> 0.1.1"}
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
          # Used by the default idempotency_key_fn to quickly determine if the request
          # can be cached. If you override idempotency_key_fn, consider checking the
          # request method in your implementation for better performance.
          # `supported_methods` is available in the opts passed to the idempotency_key_fn.
          supported_methods: ["POST", "PUT"],

          # Optional: Function reference to generate the idempotency key for a given request.
          # By default, uses the value of the "Idempotency-Key" header.
          # Must return a binary or nil. If nil is returned, the request will not be cached.
          # Default function implementation:
          #
          # fn conn, opts -> # Opts is the same as the opts passed to the plug
          #   if Enum.any?(opts.supported_methods, &(&1 == conn.method)) do
          #     conn
          #     |> Plug.Conn.get_req_header("idempotency-key") # Request headers are always downcased
          #     |> List.first()
          #   else
          #     nil
          #   end
          # end
          idempotency_key_fn: &OneAndDone.Plug.idempotency_key_from_conn/2,

          # Optional: Function reference to generate the cache key for a given request.
          # Given the conn & idempotency key (returned from idempotency_key_fn), this function
          # should return a term that will be used as the cache key.
          # By default, it returns a tuple of the module name and the idempotency key.
          # Default function implementation: fn _conn, idempotency_key -> {__MODULE__, idempotency_key}
          cache_key_fn: &OneAndDone.Plug.build_cache_key/2
      end
      ```

  That's it! POST and PUT requests will now be cached by default for 24 hours.

  ## Telemetry

  To monitor the performance of the OneAndDone plug, you can hook into `OneAndDone.Telemetry`.

  For a complete list of events, see `OneAndDone.Telemetry.events/0`.

  ### Example

  ```elixir
  # In your application.ex
  # ...
  :telemetry.attach_many(
    "one-and-done",
    OneAndDone.Telemetry.events(),
    &MyApp.Telemetry.handle_event/4,
    nil
  )
  # ...

  # In your telemetry module:
  defmodule MyApp.Telemetry do
    require Logger

    def handle_event([:one_and_done, :request, :stop], measurements, _metadata, _config) do
      duration = System.convert_time_unit(measurements.duration, :native, :millisecond)

      Logger.info("Running one_and_done took #\{duration\}ms")

      :ok
    end

    # Catch-all for unhandled events
    def handle_event(_, _, _, _) do
      :ok
    end
  end
  ```

  """

  @behaviour Plug

  alias OneAndDone.Response
  alias OneAndDone.Telemetry

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
      cache: Keyword.get(opts, :cache) || raise(OneAndDone.Errors.CacheMissingError),
      ttl: Keyword.get(opts, :ttl, @ttl),
      supported_methods: Keyword.get(opts, :supported_methods, @supported_methods),
      idempotency_key_fn:
        Keyword.get(opts, :idempotency_key_fn, &__MODULE__.idempotency_key_from_conn/2),
      cache_key_fn: Keyword.get(opts, :cache_key_fn, &__MODULE__.build_cache_key/2)
    }
  end

  @impl Plug
  def call(conn, opts) do
    Telemetry.span(:request, %{conn: conn, opts: opts}, fn ->
      idempotency_key = opts.idempotency_key_fn.(conn, opts)
      handle_idempotent_request(conn, idempotency_key, opts)
    end)
  end

  # If we didn't get an idempotency key, move on
  defp handle_idempotent_request(conn, nil, _) do
    Telemetry.event([:request, :idempotency_key_not_set], %{}, %{conn: conn})

    conn
  end

  defp handle_idempotent_request(conn, idempotency_key, opts) do
    case check_cache(conn, idempotency_key, opts) do
      {:ok, cached_response} ->
        Telemetry.event([:request, :cache_hit], %{}, %{
          idempotency_key: idempotency_key,
          conn: conn,
          response: cached_response
        })

        handle_cache_hit(conn, cached_response)

      # Cache miss passes through; we cache the response in the response callback
      _ ->
        Telemetry.event([:request, :cache_miss], %{}, %{
          idempotency_key: idempotency_key,
          conn: conn
        })

        Plug.Conn.register_before_send(conn, fn conn ->
          cache_response(conn, idempotency_key, opts)
        end)
    end
  end

  defp check_cache(conn, idempotency_key, opts) do
    Telemetry.span([:request, :cache_get], %{conn: conn, idempotency_key: idempotency_key}, fn ->
      conn
      |> opts.cache_key_fn.(idempotency_key)
      |> opts.cache.get()
    end)
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
      |> Plug.Conn.put_resp_header("idempotent-replayed", "true")

    Plug.Conn.send_resp(conn, response.status, response.body)
    |> Plug.Conn.halt()
  end

  defp cache_response(conn, idempotency_key, opts) do
    Telemetry.span(
      [:request, :put_cache],
      %{idempotency_key: idempotency_key, conn: conn},
      fn ->
        response = Response.build_response(conn)

        conn
        |> opts.cache_key_fn.(idempotency_key)
        |> opts.cache.put({:ok, response}, ttl: opts.ttl)

        conn
      end
    )
  end

  # These functions must be public to avoid an ArgumentError during compilation.

  @doc false
  def idempotency_key_from_conn(%Plug.Conn{} = conn, opts) do
    if Enum.any?(opts.supported_methods, &(&1 == conn.method)) do
      conn
      |> Plug.Conn.get_req_header("idempotency-key")
      |> List.first()
    else
      nil
    end
  end

  @doc false
  def build_cache_key(_conn, idempotency_key), do: {__MODULE__, idempotency_key}
end
