defmodule OneAndDone.Response do
  @moduledoc """
  A basic module for capturing the essence of a response.

  Response structs are stored in the cache so that idempotent requests can be
  quickly returned.

  See OneAndDone.Response.Parser for turning an inbound connection (e.g. a Plug.Conn)
  into a OneAndDone.Response.
  """

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          body: iodata(),
          cookies: %{optional(binary) => map()},
          headers: [{binary(), binary()}]
        }

  defstruct [
    :status,
    :body,
    :cookies,
    :headers
  ]

  @spec build_response(any) :: OneAndDone.Response.t()
  defdelegate build_response(value), to: OneAndDone.Response.Parser
end
