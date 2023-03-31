defimpl OneAndDone.Parser, for: Plug.Conn do
  @moduledoc """
  Turns a `Plug.Conn` into a `OneAndDone.Request` `OneAndDone.Response`.
  """

  alias OneAndDone.Request
  alias OneAndDone.Response

  @doc """
  Builds a OneAndDone.Response from a Plug.Conn.
  """
  @spec build_request(Plug.Conn.t()) :: OneAndDone.Request.t()
  def build_request(%Plug.Conn{} = conn) do
    request = %Request{
      host: conn.host,
      port: conn.port,
      scheme: conn.scheme,
      method: conn.method,
      path: conn.request_path,
      query_string: conn.query_string,
      body: conn.body_params
    }

    case request do
      %Request{body: %Plug.Conn.Unfetched{}} -> raise OneAndDone.Errors.UnfetchedBodyError
      _ -> request
    end
  end

  @doc """
  Builds a OneAndDone.Response from a Plug.Conn.
  """
  @spec build_response(Plug.Conn.t()) :: OneAndDone.Response.t()
  def build_response(%Plug.Conn{} = conn) do
    %Response{
      request_hash: OneAndDone.Parser.build_request(conn) |> OneAndDone.Request.hash(),
      status: conn.status,
      body: conn.resp_body,
      cookies: conn.resp_cookies,
      headers: conn.resp_headers
    }
  end
end
