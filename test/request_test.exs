defmodule OneAndDone.ResponseTest do
  @moduledoc false
  use ExUnit.Case
  use Plug.Test

  doctest OneAndDone.Response
  alias OneAndDone.Response

  describe "from_conn/1" do
    test "converts a conn into a response struct" do
      conn = conn(:get, "/hello") |> Plug.Conn.send_resp(200, "Hello World")
      response = Response.from_conn(conn)
      assert response.body == conn.resp_body
      assert response.cookies == conn.resp_cookies
      assert response.headers == conn.resp_headers
      assert response.status == conn.status
    end
  end
end
