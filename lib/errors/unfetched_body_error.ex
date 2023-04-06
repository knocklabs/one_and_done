defmodule OneAndDone.Errors.UnfetchedBodyError do
  @moduledoc """
  Raised when a request's body has not been fetched.

  We compare each request body to the original request body to ensure that
  the request body has not been modified. If the body has not been fetched,
  we cannot compare it to the original request body, so we raise this error.
  """

  defexception message: """
               A request's body has not been fetched. This is likely due to a missing `Plug.Parsers` plug.

               If the body has not been parsed yet, it cannot be compared to the original request body.
               This is done to prevent accidental misuse of the idempotency key.

               You have two options:

               1. Add a `Plug.Parsers` plug before the `OneAndDone.Plug` plug in your router (See `Plug` docs here: https://hexdocs.pm/plug/Plug.Parsers.html).
               2. Set the `OneAndDone.Plug` plug's `:ignore_body` option to `true`:

                   plug OneAndDone.Plug, cache: MyApp.Cache, ignore_body: true
               """
end
