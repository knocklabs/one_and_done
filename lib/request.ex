defmodule OneAndDone.Request do
  @moduledoc """
  Capture the request information that we want to cache.

  Headers are not included in the cache key because they can change
  from request to request and should not influence the substance of
  the request being made to a controller.

  Generally we do not cache this Request struct, but we do cache the
  hash of the struct so that we can compare subsequent requests to
  the original request. If the hashes don't match, we return an error.
  If the hashes do match, then we can continue processing.
  """

  @type t :: %__MODULE__{
          host: binary(),
          port: non_neg_integer(),
          scheme: binary(),
          method: binary(),
          path: binary(),
          query_string: binary(),
          body: binary()
        }

  @enforce_keys [
    :host,
    :port,
    :scheme,
    :method,
    :path,
    :query_string,
    :body
  ]

  defstruct @enforce_keys

  @doc """
  Hashes the request struct.
  """
  @spec hash(t()) :: non_neg_integer()
  def hash(%__MODULE__{} = request) do
    :erlang.phash2(request)
  end
end
