defprotocol OneAndDone.Response.Parser do
  @moduledoc """
  Protocol for turning an inbound connection (e.g. a Plug.Conn) into a OneAndDone.Response.
  """
  @spec build_response(t) :: OneAndDone.Response.t()
  def build_response(value)
end
