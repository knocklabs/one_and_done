defprotocol OneAndDone.Parser do
  @moduledoc """
  Protocol for turning an inbound connection (e.g. a Plug.Conn) into a
  OneAndDone.Request or a OneAndDone.Response.
  """

  @spec build_request(t) :: OneAndDone.Request.t()
  def build_request(value)

  @spec build_response(t) :: OneAndDone.Response.t()
  def build_response(value)
end
