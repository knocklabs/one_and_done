defmodule OneAndDone.Errors.CacheMissingError do
  @moduledoc """
  Raised when a cache is not configured. Check the docs for the OneAndDone module
  you are using (e.g. `OneAndDone.Plug`) for details on how to configure a cache.
  """

  defexception message: """
               A cache was not configured for OneAndDone. Check the docs for
               the OneAndDone module you are using (e.g. OneAndDone.Plug) for
               details on how to configure a cache.
               """
end
