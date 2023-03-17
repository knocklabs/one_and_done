defmodule OneAndDone.PlugMacro do
  @moduledoc """
    Starting over with this: going to instead just use plug opts.

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

  2. Create a new module that uses `OneAndDone.Plug`:

      ```elixir
      defmodule MyApp.Plugs.Idempotent do
        use OneAndDone.Plug,
        otp_app: :my_app
      end
      ```

    Then, configure the plug in your `config/config.exs`:

      ```elixir
      config :my_app, MyApp.Plugs.Idempotent,
        # Required: must conform to OneAndDone.Cache (e.g. Nebulex.Cache)
        cache: MyApp.Cache,
        # Optional: How long to keep entries, defaults to 86_400 (24 hours)
        ttl: 86_400,
        # Optional: Function to generate the cache key for a given request.
        # By default, uses the value of the "Idempotency-Key" header.
        # Must return a binary or nil. If nil is returned, the request will not be cached.
        cache_key_fn: fn conn -> Plug.Conn.get_req_header(conn, "Some other header") end,



            cache: MyApp.Cache, # Cache must conform to Nebulex.Cache
        # The following fields are optional
        ttl: 86_400, # 24 hours (default)
        # Function to generate the cache key for a given request.
        # By default, uses the value of the "Idempotency-Key" header.
        # Custom cache key functions must return a binary or nil.
        # If nil is returned, the request will not be cached.
        cache_key_fn: fn conn -> Plug.Conn.get_req_header(conn, "Idempotency-Key") end, # (default)

      ```

  3. Add the plug to your router:

      ```elixir
      pipeline :api do
        plug MyApp.Plugs.Idempotent
      end
      ```

      That's it! POST and PUT requests will now be cached by default for 24 hours.

      Stuff to add

      1. Ability to customize the cache key function

      Down the road, I'd like to be able to customize the following per route:

      1. Cache key function
      2. TTL
      3. Cache
      4. Whether or not we should cache the request in the first place
  """

  import Plug.Conn

  alias OneAndDone.Response

  # Macro to define a plug
  defmacro __using__(otp_app: app_name) do
    opts = Application.get_env(app_name, __MODULE__, [])

    cache = Keyword.get(opts, :cache)

    if is_nil(cache) do
      raise ArgumentError, "You must specify a cache in your config"
    end

    cache_key_fn = Keyword.get(opts, :cache_key_fn, &cache_key_for_conn/1)
    ttl = Keyword.get(opts, :ttl, 86_400)

    quote do
      @cache unquote(cache)
      @ttl unquote(ttl)
      @cache_key_fn unquote(cache_key_fn)

      def init(opts), do: opts

      @supported_methods ["POST", "PUT"]

      def call(conn, _opts) do
        case conn.method do
          method when method in @supported_methods ->
            if @cache_key_fn conn do
              handle_idempotent_request(conn)
            else
              conn
            end

          _ ->
            conn
        end
      end

      defp handle_idempotent_request(conn) do
        cache_key = @cache_key_fn conn

        case @cache.get(cache_key) do
          {:ok, cached_response} -> handle_cache_hit(conn, cached_response)
          # Cache miss passes through; we cache the response in the response callback
          _ -> register_before_send(conn, &cache_response/1)
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

      defp cache_response(conn) do
        cache_key = @cache_key_fn conn
        response = Response.from_conn(conn)
        @cache.put(cache_key, {:ok, response}, ttl: @ttl)

        conn
      end
    end
  end

  defp cache_key_for_conn(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, "idempotency-key") do
      [key | _] -> key
      [] -> nil
    end
  end
end
