defprotocol OneAndDone.Response.Parser do
  @spec build_response(t) :: OneAndDone.Response.t()
  def build_response(value)
end
