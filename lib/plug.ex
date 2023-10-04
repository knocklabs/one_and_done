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

          # Optional: Function reference to generate an idempotence TTL per request.
          # Takes the current `Plug.Conn` as the first argument and the current
          # `idempotency_key` as the second.
          #
          # When provided, this function is called before falling back to the
          # `ttl` option.
          #
          # Defaults to `nil`.
          build_ttl_fn: &OneAndDone.Plug.build_ttl/2,

          # Optional: Which methods to cache, defaults to ["POST", "PUT"]
          # Used by the default idempotency_key_fn to quickly determine if the request
          # can be cached. If you override idempotency_key_fn, consider checking the
          # request method in your implementation for better performance.
          # `supported_methods` is available in the opts passed to the idempotency_key_fn.
          supported_methods: ["POST", "PUT"],

          # Optional: Which response headers to ignore when caching, defaults to ["x-request-id"]
          # When returning a cached response, some headers should not be modified by the contents of the cache.
          #
          # Instead, the ignored headers are returned with the prefix `original-`.
          #
          # By default, the `x-request-id` header is not modified. This means that each request will have a
          # unique `x-request-id` header, even if a cached response is returned for a request. The original request
          # ID is still available under `original-x-request-id`.
          #
          # If you are using a framework that sets a different header for request IDs, you can add it to this list.
          ignored_response_headers: ["x-request-id"],

          # Optional: Function reference to generate the idempotency key for a given request.
          # By default, uses the value of the `Idempotency-Key` header.
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

          # Optional: Flag to enable request match checking. Defaults to true.
          # If true, the function given in check_requests_match_fn will be called to determine if the
          # original request matches the current request.
          # If false, no such check shall be performed.
          request_matching_checks_enabled: true,

          # Optional: Function reference to determine if the original request matches the current request.
          # Given the current connection and a hash of the original request, this function should return
          # true if the current request matches the original request.
          # By default, uses `:erlang.phash2/2` to generate a hash of the current request. If the `hashes`
          # do not match, the request is not idempotent and One and Done will return a 400 response.
          # To disable this check, use `fn _conn, _original_request_hash -> true end`
          # Default function implementation:
          #
          # fn conn, original_request_hash ->
          #   request_hash =
          #     Parser.build_request(conn)
          #     |> Request.hash()
          #
          #   cached_response.request_hash == request_hash
          # end
          check_requests_match_fn: &OneAndDone.Plug.matching_request?/2,

          # Optional: Max length of each idempotency key. Defaults to 255 characters.
          # If the idempotency key is longer than this, we respond with error 400.
          # Set to 0 to disable this check.
          max_key_length: 255
      end
      ```

  That's it! POST and PUT requests will now be cached by default for 24 hours.

  ## Response headers
  By default, the "x-request-id" header is not modified. This means that each request will have a
  unique "x-request-id" header, even if a cached response is returned for a request.
  By default, the "original-x-request-id" header is set to the value of the "x-request-id" header
  from the original request. This is useful for tracing the original request that was cached.
  One and Done sets the "idempotent-replayed" header to "true" if a cached response is returned.

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

  alias OneAndDone.Parser
  alias OneAndDone.Request
  alias OneAndDone.Telemetry

  @supported_methods ["POST", "PUT"]
  @ttl :timer.hours(24)
  @default_max_key_length 255

  @impl Plug
  @spec init(cache: OneAndDone.Cache.t()) :: %{
          cache: any,
          ttl: any,
          build_ttl_fn: any,
          supported_methods: any,
          ignored_response_headers: any,
          idempotency_key_fn: any,
          cache_key_fn: any,
          request_matching_checks_enabled: boolean(),
          check_requests_match_fn: any,
          max_key_length: non_neg_integer()
        }
  def init(opts) do
    %{
      cache: Keyword.get(opts, :cache) || raise(OneAndDone.Errors.CacheMissingError),
      ttl: Keyword.get(opts, :ttl, @ttl),
      build_ttl_fn: Keyword.get(opts, :build_ttl_fn),
      supported_methods: Keyword.get(opts, :supported_methods, @supported_methods),
      ignored_response_headers: Keyword.get(opts, :ignored_response_headers, ["x-request-id"]),
      idempotency_key_fn:
        Keyword.get(opts, :idempotency_key_fn, &__MODULE__.idempotency_key_from_conn/2),
      cache_key_fn: Keyword.get(opts, :cache_key_fn, &__MODULE__.build_cache_key/2),
      request_matching_checks_enabled: Keyword.get(opts, :request_matching_checks_enabled, true),
      check_requests_match_fn:
        Keyword.get(opts, :check_requests_match_fn, &__MODULE__.matching_request?/2),
      max_key_length: validate_max_key_length!(opts)
    }
  end

  defp validate_max_key_length!(opts) do
    case Keyword.get(opts, :max_key_length, @default_max_key_length) do
      number when is_integer(number) and number >= 0 -> number
      _ -> raise(OneAndDone.Errors.InvalidMaxKeyLengthError)
    end
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
        handle_cache_hit(conn, cached_response, idempotency_key, opts)

      {:error, :idempotency_key_too_long} ->
        handle_idempotency_key_too_long(conn, idempotency_key, opts)

      # Cache miss passes through; we cache the response in the response callback
      _ ->
        handle_cache_miss(conn, idempotency_key, opts)
    end
  end

  defp check_cache(conn, idempotency_key, opts) do
    if opts.max_key_length > 0 and String.length(idempotency_key) > opts.max_key_length do
      {:error, :idempotency_key_too_long}
    else
      Telemetry.span(
        [:request, :cache_get],
        %{conn: conn, idempotency_key: idempotency_key},
        fn ->
          conn
          |> opts.cache_key_fn.(idempotency_key)
          |> opts.cache.get()
        end
      )
    end
  end

  defp handle_cache_hit(conn, response, idempotency_key, opts) do
    if opts.request_matching_checks_enabled and not opts.check_requests_match_fn.(conn, response) do
      handle_request_mismatch(conn, response, idempotency_key)
    else
      send_idempotent_response(conn, response, idempotency_key, opts)
    end
  end

  defp handle_cache_miss(conn, idempotency_key, opts) do
    Telemetry.event([:request, :cache_miss], %{}, %{
      idempotency_key: idempotency_key,
      conn: conn
    })

    Plug.Conn.register_before_send(conn, fn conn ->
      cache_response(conn, idempotency_key, opts)
    end)
  end

  defp handle_idempotency_key_too_long(conn, idempotency_key, opts) do
    Telemetry.event(
      [:request, :idempotency_key_too_long],
      %{key_length: String.length(idempotency_key), key_length_limit: opts.max_key_length},
      %{
        idempotency_key: idempotency_key,
        conn: conn
      }
    )

    Plug.Conn.send_resp(conn, 400, "{\"error\": \"idempotency_key_too_long\"}")
  end

  defp cache_response(conn, idempotency_key, opts) do
    if conn.status >= 400 and conn.status < 500 do
      Telemetry.event([:request, :skip_put_cache], %{}, %{
        idempotency_key: idempotency_key,
        conn: conn
      })

      conn
    else
      Telemetry.span(
        [:request, :put_cache],
        %{idempotency_key: idempotency_key, conn: conn},
        fn ->
          response = Parser.build_response(conn)
          ttl = build_ttl(conn, idempotency_key, opts)

          conn
          |> opts.cache_key_fn.(idempotency_key)
          |> opts.cache.put({:ok, response}, ttl: ttl)

          conn
        end
      )
    end
  end

  defp build_ttl(conn, idempotency_key, %{build_ttl_fn: build_ttl_fn} = opts)
       when is_function(build_ttl_fn, 2) do
    case build_ttl_fn.(conn, idempotency_key) do
      ttl when is_integer(ttl) -> ttl
      _ -> opts.ttl
    end
  end

  defp build_ttl(_, _, opts), do: opts.ttl

  defp handle_request_mismatch(conn, response, idempotency_key) do
    Telemetry.event(
      [:request, :request_mismatch],
      %{},
      %{
        idempotency_key: idempotency_key,
        conn: conn,
        response: response
      }
    )

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(
      400,
      "{\"error\": \"This request does not match the first request used with this idempotency key. This could mean you are reusing idempotency keys across requests. Either make sure the request matches across idempotent requests, or change your idempotency key when making new requests.\"}"
    )
    |> Plug.Conn.halt()
  end

  defp send_idempotent_response(conn, response, idempotency_key, opts) do
    Telemetry.event([:request, :cache_hit], %{}, %{
      idempotency_key: idempotency_key,
      conn: conn,
      response: response
    })

    conn =
      Enum.reduce(response.cookies, conn, fn {key, %{value: value}}, conn ->
        Plug.Conn.put_resp_cookie(conn, key, value)
      end)

    conn =
      Enum.reduce(response.headers, conn, fn
        {key, value}, conn ->
          if key in opts.ignored_response_headers do
            Plug.Conn.put_resp_header(conn, "original-#{key}", value)
          else
            Plug.Conn.put_resp_header(conn, key, value)
          end
      end)
      |> Plug.Conn.put_resp_header("idempotent-replayed", "true")

    Plug.Conn.send_resp(conn, response.status, response.body)
    |> Plug.Conn.halt()
  end

  # These functions must be public to avoid an ArgumentError during compilation.

  def matching_request?(conn, cached_response) do
    request_hash =
      Parser.build_request(conn)
      |> Request.hash()

    cached_response.request_hash == request_hash
  end

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
  def build_cache_key(conn, idempotency_key),
    do: {__MODULE__, conn.method, conn.request_path, idempotency_key}
end
