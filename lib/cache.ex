defmodule OneAndDone.Cache do
  @moduledoc """
  Defines the most basic cache interface.

  Should be compliant with [Nebulex's cache](https://hexdocs.pm/nebulex/Nebulex.Cache.html).
  """

  @doc """
  Retreive a value from the cache.
  """
  @callback get(key :: any()) :: any | nil

  @doc """
  Store a value in the cache under the given key.

  Opts must include a TTL, given in milliseconds.
  """
  @callback put(key :: any(), value :: any(), opts :: [ttl: pos_integer()]) :: :ok
end
