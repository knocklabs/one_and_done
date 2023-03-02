defmodule OneAndDone.Cache do
  @moduledoc """
  Defines the most basic cache interface.

  Should be compliant with [Nebulex's cache](https://hexdocs.pm/nebulex/Nebulex.Cache.html).
  """

  @doc """
  Retreive a value from the cache.
  """
  @callback get(key :: any(), opts :: Keyword.t()) :: any | nil

  @doc """
  Put a value into the cache.
  """
  @callback put(key :: any(), value :: any(), opts :: Keyword.t()) :: :ok
end
