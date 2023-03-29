# One and Done

One and Done is the easiest way to make HTTP requests idempotent in Elixir applications.

One and Done supports the following frameworks:

* `Plug` (including `Phoenix`)

## Usage

One and Done depends on having a pre-existing cache like [Nebulex](https://hexdocs.pm/nebulex/Nebulex.html). This guide assumes Nebulex is already configured under `MyApp.Cache`.

1. Add `one_and_done` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:one_and_done, "~> 0.1.0"}
  ]
end
```

2. Add `OneAndDone` to your `Plug` pipeline:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :api do
    # Configuration options for OneAndDone are in the docs
    plug OneAndDone.Plug, cache: MyApp.Cache
  end

  # By default, all POST and PUT requests piped through :api
  # that have an Idempotency-Key header set will be cached for 24 hours.
  scope "/api", MyAppWeb do
    pipe_through :api

    resources "/users", UserController
  end
end
```

3. Make your requests idempotent by adding the `Idempotency-Key` header:

```shell

curl -X POST \
  http://localhost:4000/api/users \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: 123' \
  -d '{
  "email": "hello@example.com",
  "password": "password"
  }'
```

Repeat the request with the same `Idempotency-Key` header and you will get the same response
without the request being processed again.

