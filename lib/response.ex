defmodule OneAndDone.Response do
  @moduledoc """
  A basic module for capturing the essence of a response.

  See OneAndDone.Response.Parser for turning an inbound connection (e.g. a Plug.Conn)
  into a OneAndDone.Response.
  """

  defstruct [
    :status,
    :body,
    :cookies,
    :headers
  ]

  defdelegate build_response(value), to: OneAndDone.Response.Parser
end
