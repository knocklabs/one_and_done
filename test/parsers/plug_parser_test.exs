defmodule OneAndDone.PlugParserTest do
  @moduledoc false
  use ExUnit.Case
  use Plug.Test

  alias OneAndDone.Parser

  describe "build_request/1" do
    test "converts a conn into a request struct" do
      conn =
        conn(:get, "/hello", "some-body")
        |> Plug.run([{Plug.Parsers, parsers: [{:json, json_decoder: Jason}], pass: ["*/*"]}])
        |> Plug.Conn.send_resp(200, "Hello World")

      request = Parser.build_request(conn)

      assert request.host == conn.host
      assert request.method == conn.method
      assert request.path == conn.request_path
      assert request.port == conn.port
      assert request.scheme == conn.scheme
      assert request.query_string == conn.query_string
    end

    test "throws an error if the body is not available" do
      conn =
        conn(:get, "/hello", "some-body")
        |> Plug.Conn.send_resp(200, "Hello World")

      assert_raise OneAndDone.Errors.UnfetchedBodyError, fn ->
        Parser.build_request(conn)
      end
    end
  end

  describe "build_response/1" do
    test "converts a conn into a response struct" do
      conn =
        conn(:post, "/hello?key=value#something", "{\"some\": \"json\"}")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("some-header", "some-value")
        |> Plug.run([{Plug.Parsers, parsers: [{:json, json_decoder: Jason}], pass: ["*/*"]}])
        |> Plug.Conn.send_resp(200, "Hello World")

      response = Parser.build_response(conn)
      assert response.request_hash == Parser.build_request(conn) |> OneAndDone.Request.hash()
      assert response.body == conn.resp_body
      assert response.cookies == conn.resp_cookies
      assert response.headers == conn.resp_headers
      assert response.status == conn.status
    end
  end
end
