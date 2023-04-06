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

    def get(key) do
      Agent.get(__MODULE__, fn cache ->
        with {:ok, ttl} <- Map.fetch(cache.ttls, key),
             :gt <- DateTime.compare(ttl, DateTime.utc_now()) do
          Map.get(cache.data, key)
        else
          _ -> nil
        end
      end)
    end

    def put(key, value, opts) do
      ttl = Keyword.fetch!(opts, :ttl)

      Agent.update(__MODULE__, fn cache ->
        cache
        |> put_in([:ttls, key], DateTime.utc_now() |> DateTime.add(ttl, :millisecond))
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

  describe "init/1" do
    test "raises an error if the cache is not set" do
      assert_raise OneAndDone.Errors.CacheMissingError, fn ->
        OneAndDone.Plug.init([])
      end
    end

    test "raises an error if the max_key_length is invalid" do
      assert_raise OneAndDone.Errors.InvalidMaxKeyLengthError, fn ->
        OneAndDone.Plug.init(cache: TestCache, max_key_length: "invalid")
      end

      assert_raise OneAndDone.Errors.InvalidMaxKeyLengthError, fn ->
        OneAndDone.Plug.init(cache: TestCache, max_key_length: -1)
      end

      assert_raise OneAndDone.Errors.InvalidMaxKeyLengthError, fn ->
        OneAndDone.Plug.init(cache: TestCache, max_key_length: 1.5)
      end

      assert_raise OneAndDone.Errors.InvalidMaxKeyLengthError, fn ->
        OneAndDone.Plug.init(cache: TestCache, max_key_length: :one)
      end

      assert_raise OneAndDone.Errors.InvalidMaxKeyLengthError, fn ->
        OneAndDone.Plug.init(cache: TestCache, max_key_length: :infinity)
      end

      assert_raise OneAndDone.Errors.InvalidMaxKeyLengthError, fn ->
        OneAndDone.Plug.init(cache: TestCache, max_key_length: [1, 2, 3])
      end

      assert_raise OneAndDone.Errors.InvalidMaxKeyLengthError, fn ->
        OneAndDone.Plug.init(cache: TestCache, max_key_length: %{"key" => "123"})
      end

      assert_raise OneAndDone.Errors.InvalidMaxKeyLengthError, fn ->
        OneAndDone.Plug.init(cache: TestCache, max_key_length: [key: 123])
      end
    end
  end

  @pre_plugs [{Plug.Parsers, parsers: [{:json, json_decoder: Jason}], pass: ["*/*"]}]

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
          conn(method, "/hello", Jason.encode!("some-body"))
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.Conn.put_req_header("content-type", "application/json")
          |> Plug.run(@pre_plugs)

        conn =
          original_conn
          |> Plug.run([{OneAndDone.Plug, cache: TestCache}])
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.put_resp_cookie("some-cookie", "value")
          |> Plug.Conn.put_resp_header("some-header", "value")
          |> Plug.Conn.send_resp(200, "Okay!")

        method_str = method |> Atom.to_string() |> String.upcase()

        refute Plug.run(original_conn, [{OneAndDone.Plug, cache: TestCache}]) == conn
        struct = TestCache.get({OneAndDone.Plug, method_str, "/hello", cache_key}) |> elem(1)

        assert struct == %OneAndDone.Response{
                 request_hash:
                   OneAndDone.Parser.build_request(original_conn) |> OneAndDone.Request.hash(),
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
          conn(method, "/hello", Jason.encode!("some-body"))
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.Conn.put_req_header("content-type", "application/json")
          |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.put_resp_cookie("some-cookie", "value")
          |> Plug.Conn.put_resp_header("some-header", "value")
          |> Plug.Conn.send_resp(200, "Okay!")

        new_conn =
          conn(method, "/hello", Jason.encode!("some-body"))
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.Conn.put_req_header("content-type", "application/json")
          |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])

        assert new_conn.resp_body == original_conn.resp_body
        assert new_conn.resp_cookies == original_conn.resp_cookies

        assert new_conn.resp_headers -- [{"idempotent-replayed", "true"}] ==
                 original_conn.resp_headers

        assert new_conn.status == original_conn.status
      end)
    end

    test "when we've seen a request before, it halts the processing pipeline" do
      [:post, :put]
      |> Enum.each(fn method ->
        cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

        _original_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.put_resp_cookie("some-cookie", "value")
          |> Plug.Conn.put_resp_header("some-header", "value")
          |> Plug.Conn.send_resp(200, "Okay!")

        new_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])

        assert new_conn.state == :sent
      end)
    end

    test "when we've seen a request before, the idempotent-replayed header is set" do
      [:post, :put]
      |> Enum.each(fn method ->
        cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

        original_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.put_resp_cookie("some-cookie", "value")
          |> Plug.Conn.put_resp_header("some-header", "value")
          |> Plug.Conn.send_resp(200, "Okay!")

        new_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])

        assert Plug.Conn.get_resp_header(new_conn, "idempotent-replayed") == ["true"]
        refute Plug.Conn.get_resp_header(original_conn, "idempotent-replayed") == ["true"]
      end)
    end

    test "requests that return error 4xx are not cached" do
      [:post, :put]
      |> Enum.each(fn method ->
        cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

        _original_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run([{OneAndDone.Plug, cache: TestCache}])
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.put_resp_cookie("some-cookie", "value")
          |> Plug.Conn.put_resp_header("some-header", "value")
          |> Plug.Conn.send_resp(400, "Not okay!")

        new_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run([{OneAndDone.Plug, cache: TestCache}])

        refute Plug.Conn.get_resp_header(new_conn, "idempotent-replayed") == ["true"]
        refute TestCache.get({OneAndDone.Plug, cache_key})
      end)
    end

    test "by default, ignores x-request-id and returns original-x-request-id for the original request's x-request-id" do
      [:post, :put]
      |> Enum.each(fn method ->
        cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

        original_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.put_resp_cookie("some-cookie", "value")
          |> Plug.Conn.put_resp_header("some-header", "value")
          |> Plug.Conn.put_resp_header("x-request-id", "1234")
          |> Plug.Conn.send_resp(200, "Okay!")

        new_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.Conn.put_resp_header("x-request-id", "5678")
          |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])

        refute Plug.Conn.get_resp_header(new_conn, "x-request-id") ==
                 Plug.Conn.get_resp_header(original_conn, "x-request-id")

        assert Plug.Conn.get_resp_header(new_conn, "original-x-request-id") ==
                 Plug.Conn.get_resp_header(original_conn, "x-request-id")
      end)
    end

    test "ignored response headers are returned without modification, but the original matching header is still returned" do
      [:post, :put]
      |> Enum.each(fn method ->
        cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

        _original_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.run(
            @pre_plugs ++
              [
                {OneAndDone.Plug, cache: TestCache, ignored_response_headers: ["some-header"]}
              ]
          )
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.put_resp_cookie("some-cookie", "value")
          |> Plug.Conn.put_resp_header("some-header", "value")
          |> Plug.Conn.send_resp(200, "Okay!")

        new_conn =
          conn(method, "/hello")
          |> Plug.Conn.put_req_header("idempotency-key", cache_key)
          |> Plug.Conn.put_resp_header("some-header", "not the same value")
          |> Plug.run(
            @pre_plugs ++
              [
                {OneAndDone.Plug, cache: TestCache, ignored_response_headers: ["some-header"]}
              ]
          )

        assert ["not the same value"] == Plug.Conn.get_resp_header(new_conn, "some-header")
        assert ["value"] == Plug.Conn.get_resp_header(new_conn, "original-some-header")
      end)
    end

    test "respects TTL" do
      cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

      original_conn =
        conn(:post, "/hello", Jason.encode!("some-body"))
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache, ttl: 0}])
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.put_resp_cookie("some-cookie", "value")
        |> Plug.Conn.put_resp_header("some-header", "value")
        |> Plug.Conn.send_resp(200, "Okay!")

      Process.sleep(10)

      new_conn =
        conn(:post, "/hello")
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.put_resp_cookie("some-cookie", "different value")
        |> Plug.Conn.put_resp_header("some-header", "different value")
        |> Plug.Conn.send_resp(201, "Different response")

      refute new_conn.resp_body == original_conn.resp_body
      refute new_conn.resp_cookies == original_conn.resp_cookies
      refute new_conn.resp_headers == original_conn.resp_headers
      refute new_conn.status == original_conn.status
    end

    test "if two requests share the same key and path but have different methods, it doesn't matter" do
      cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

      original_conn =
        conn(:post, "/hello", Jason.encode!("some-body"))
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.put_resp_cookie("some-cookie", "value")
        |> Plug.Conn.put_resp_header("some-header", "value")
        |> Plug.Conn.send_resp(200, "Okay!")

      failed_conn =
        conn(:put, "/hello", Jason.encode!(%{"key" => "different-body"}))
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.put_resp_cookie("some-cookie", "different-value")
        |> Plug.Conn.put_resp_header("some-header", "different-value")
        |> Plug.Conn.send_resp(204, "Different Okay!")

      refute failed_conn.resp_body == original_conn.resp_body
      refute failed_conn.resp_cookies == original_conn.resp_cookies
      refute failed_conn.resp_headers == original_conn.resp_headers
      refute failed_conn.status == original_conn.status
    end

    test "if two requests share the same key and method but have different paths, it doesn't matter" do
      cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

      original_conn =
        conn(:post, "/hello", Jason.encode!("some-body"))
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.put_resp_cookie("some-cookie", "value")
        |> Plug.Conn.put_resp_header("some-header", "value")
        |> Plug.Conn.send_resp(200, "Okay!")

      failed_conn =
        conn(:post, "/hello-again", Jason.encode!(%{"key" => "different-body"}))
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.put_resp_cookie("some-cookie", "different-value")
        |> Plug.Conn.put_resp_header("some-header", "different-value")
        |> Plug.Conn.send_resp(204, "Different Okay!")

      refute failed_conn.resp_body == original_conn.resp_body
      refute failed_conn.resp_cookies == original_conn.resp_cookies
      refute failed_conn.resp_headers == original_conn.resp_headers
      refute failed_conn.status == original_conn.status
    end

    test "if two requests share the same key but don't match, it fails" do
      cache_key = :rand.uniform(1_000_000) |> Integer.to_string()

      original_conn =
        conn(:post, "/hello", Jason.encode!(%{"key" => "some-body"}))
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.put_resp_cookie("some-cookie", "value")
        |> Plug.Conn.put_resp_header("some-header", "value")
        |> Plug.Conn.send_resp(200, "Okay!")

      failed_conn =
        conn(:post, "/hello", Jason.encode!(%{"key" => "different-body"}))
        |> Plug.Conn.put_req_header("idempotency-key", cache_key)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.run(@pre_plugs ++ [{OneAndDone.Plug, cache: TestCache}])

      refute failed_conn.resp_body == original_conn.resp_body
      refute failed_conn.resp_cookies == original_conn.resp_cookies
      refute failed_conn.resp_headers == original_conn.resp_headers
      refute failed_conn.status == original_conn.status
    end
  end
end
