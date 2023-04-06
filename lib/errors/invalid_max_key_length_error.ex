defmodule OneAndDone.Errors.InvalidMaxKeyLengthError do
  @moduledoc """
  Raised when the configured cache key is not an integer greater than or equal to 0.
  """

  defexception message:
                 "`max_key_length` was set to an invalid value. It must be an integer greater than or equal to 0."
end
