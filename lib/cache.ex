defmodule OneAndDone.Cache do
  @moduledoc """
  Defines the most basic cache interface.

  This module is used as a reference for Cache implementations. Although not used by
  OneAndDone, Cache implementations should be compliant with this module.

  This module is compliant with `Nebulex.Cache`. If you use Nebulex, you
  are already compliant with this module.
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
