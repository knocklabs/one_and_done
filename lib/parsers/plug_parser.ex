defimpl OneAndDone.Response.Parser, for: Plug.Conn do
  @moduledoc """
  Turns a Plug.Conn into a OneAndDone.Response.
  """

  alias OneAndDone.Response

  def build_response(%Plug.Conn{} = conn) do
    %Response{
      status: conn.status,
      body: conn.resp_body,
      cookies: conn.resp_cookies,
      headers: conn.resp_headers
    }
  end
end
