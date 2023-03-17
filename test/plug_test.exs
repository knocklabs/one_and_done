defmodule OneAndDone.PlugTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use Plug.Test

  doctest OneAndDone.Plug

  defmodule TestCache do
    @moduledoc """
    Agent for storing cached responses under test.
    """

    use Agent
    @default_state %{data: %{}, ttls: %{}}

    def start_link(_) do
      Agent.start_link(fn -> @default_state end, name: __MODULE__)
    end

    def get(key, after_ttl \\ 0) do
      Agent.get(__MODULE__, fn cache ->
        ttl = Map.get(cache.ttls, key, :infinity)

        result = Map.get(cache.data, key)

        if ttl > after_ttl do
          result
        else
          nil
        end
      end)
    end

    def put(key, value, ttl) do
      Agent.update(__MODULE__, fn cache ->
        cache
        |> put_in([:ttls, key], ttl)
        |> put_in([:data, key], value)
      end)
    end

    def dump do
      Agent.get(__MODULE__, fn cache -> cache end)
    end

    def delete(key) do
      Agent.update(__MODULE__, fn %{data: data, ttls: ttls} ->
        %{
          data: Map.delete(data, key),
          ttls: Map.delete(ttls, key)
        }
      end)
    end

    def clear do
      Agent.update(__MODULE__, fn _ -> @default_state end)
    end
  end

  setup do
    start_supervised!(TestCache)

    :ok
  end

  @empty_cache_state %{data: %{}, ttls: %{}}

  describe "call/2" do
    test "does nothing with non-idempotent requests" do
      [:get, :delete, :patch]
      |> Enum.each(fn method ->
        conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", "123")

        assert Plug.run(conn, [{OneAndDone.Plug, cache: TestCache}]) == conn
        assert TestCache.dump() == @empty_cache_state
      end)
    end

    test "does nothing with put/post requests missing the idempotency-key header" do
      [:post, :put]
      |> Enum.each(fn method ->
        conn = conn(method, "/hello")
        assert Plug.run(conn, [{OneAndDone.Plug, cache: TestCache}]) == conn
        assert TestCache.dump() == @empty_cache_state
      end)
    end

    test "when the idempotency-key header is set, stores put/post requests in the cache" do
      [:post, :put]
      |> Enum.each(fn method ->
        cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

        original_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)

        conn =
          original_conn
          |> Plug.run([{OneAndDone.Plug, cache: TestCache}])
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.put_resp_cookie("some-cookie", "value")
          |> Plug.Conn.put_resp_header("some-header", "value")
          |> Plug.Conn.send_resp(200, "Okay!")

        refute Plug.run(original_conn, [{OneAndDone.Plug, cache: TestCache}]) == conn
        struct = TestCache.get(cache_key) |> elem(1)

        assert struct == %OneAndDone.Response{
                 body: "Okay!",
                 cookies: %{"some-cookie" => %{value: "value"}},
                 headers: [
                   {"cache-control", "max-age=0, private, must-revalidate"},
                   {"content-type", "text/plain; charset=utf-8"},
                   {"some-header", "value"}
                 ],
                 status: 200
               }
      end)
    end

    test "when we've seen a request before, we get the old response back" do
      [:post, :put]
      |> Enum.each(fn method ->
        cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

        original_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run([{OneAndDone.Plug, cache: TestCache}])
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.put_resp_cookie("some-cookie", "value")
          |> Plug.Conn.put_resp_header("some-header", "value")
          |> Plug.Conn.send_resp(200, "Okay!")

        new_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run([{OneAndDone.Plug, cache: TestCache}])

        assert new_conn.resp_body == original_conn.resp_body
        assert new_conn.resp_cookies == original_conn.resp_cookies
        assert new_conn.resp_headers == original_conn.resp_headers
        assert new_conn.status == original_conn.status
      end)
    end

    test "respects TTL" do
      cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

      original_conn =
        conn(:post, "/hello")
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.run([{OneAndDone.Plug, cache: TestCache, ttl: 0}])
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.put_resp_cookie("some-cookie", "value")
        |> Plug.Conn.put_resp_header("some-header", "value")
        |> Plug.Conn.send_resp(200, "Okay!")

      new_conn =
        conn(:post, "/hello")
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.run([{OneAndDone.Plug, cache: TestCache}])

      refute new_conn.resp_body == original_conn.resp_body
      refute new_conn.resp_cookies == original_conn.resp_cookies
      refute new_conn.resp_headers == original_conn.resp_headers
      refute new_conn.status == original_conn.status
    end
  end
end
