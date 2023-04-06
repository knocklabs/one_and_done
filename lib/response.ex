defmodule OneAndDone.Response do
  @moduledoc """
  A basic module for capturing the essence of a response.

  Also captures a hash of the request that generated the response. This is used
  to determine if two requests sharing the same idempotency key are the same
  to prevent accidental misuse of the idempotency key.

  Response structs are stored in the cache so that idempotent requests can be
  quickly returned.

  See `OneAndDone.Response.Parser` for turning an inbound connection (e.g. a Plug.Conn)
  into a `OneAndDone.Response`.
  """

  @type t :: %__MODULE__{
          request_hash: non_neg_integer(),
          status: non_neg_integer(),
          body: iodata(),
          cookies: %{optional(binary) => map()},
          headers: [{binary(), binary()}]
        }

  @enforce_keys [:request_hash, :status, :body, :cookies, :headers]
  defstruct [
    :request_hash,
    :status,
    :body,
    :cookies,
    :headers
  ]
end
