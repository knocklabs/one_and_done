defmodule OneAndDone.Telemetry do
  @moduledoc """
  Telemetry integration to track how long it takes to process a request.

  OneAndDone emits the following metrics:

  | Metric | Description | Measurements | Metadata |
  | --- | --- | --- | --- |
  | `[:one_and_done, :request, :start]` | When we begin processing a request. |  | `conn`, `opts` |
  | `[:one_and_done, :request, :stop]` | When we finish processing a request, including the duration in native units. | `duration` | `conn`, `opts` |
  | `[:one_and_done, :request, :exception]` | When we finish processing a request, if an exception was raised. Includes the duration in native units. | `duration`, `exception` | `conn`, `opts` |
  | `[:one_and_done, :request, :cache_hit]` | Given an idempotency key, we found a cached response. | `idempotency_key` | `conn`, `response` |
  | `[:one_and_done, :request, :cache_miss]` | Given an idempotency key, we didn't find a cached response. | `idempotency_key` | `conn` |
  | `[:one_and_done, :request, :idempotency_key_not_set]` | The request doesn't have an idempotency key and will not be processed further by OneAndDone. |  | `conn` |
  | `[:one_and_done, :request, :idempotency_key_too_long]` | The idempotency key is too long. A 400 error was returned to the client. | `key_length`, `key_length_limit` | `conn` |
  | `[:one_and_done, :request, :cache_get, :start]` | When we begin checking the cache for a request. |  | `conn`, `idempotency_key` |
  | `[:one_and_done, :request, :cache_get, :stop]` | When we finish checking the cache for a request, including the duration in native units. | `duration` | `conn`, `idempotency_key` |
  | `[:one_and_done, :request, :cache_get, :exception]` | When we finish checking the cache for a request, if an exception was raised. Includes the duration in native units. | `duration`, `exception` | `conn`, `idempotency_key` |
  | `[:one_and_done, :request, :cache_put, :start]` | When we begin serializing and putting a response into the cache. |  | `conn`, `idempotency_key` |
  | `[:one_and_done, :request, :cache_put, :stop]` | When we finish serializing and putting a response into the cache, including the duration in native units. | `duration` | `conn`, `idempotency_key` |
  | `[:one_and_done, :request, :cache_put, :exception]` | When we finish serializing and putting a response into the cache, if an exception was raised. Includes the duration in native units. | `duration`, `exception` | `conn`, `idempotency_key` |


  The duration is emitted in native units. To convert to milliseconds, use `System.convert_time_unit(duration, :native, :millisecond)`.

  """

  require Logger

  @events [
    [:one_and_done, :request, :start],
    [:one_and_done, :request, :stop],
    [:one_and_done, :request, :exception],
    [:one_and_done, :request, :cache_hit],
    [:one_and_done, :request, :cache_miss],
    [:one_and_done, :request, :idempotency_key_not_set],
    [:one_and_done, :request, :idempotency_key_too_long],
    [:one_and_done, :request, :cache_get, :start],
    [:one_and_done, :request, :cache_get, :stop],
    [:one_and_done, :request, :cache_get, :exception],
    [:one_and_done, :request, :cache_put, :start],
    [:one_and_done, :request, :cache_put, :stop],
    [:one_and_done, :request, :cache_put, :exception]
  ]

  @doc """
  Return the list of events emitted by this module.
  """
  @spec events() :: list()
  def events, do: @events

  defmodule SpanResult do
    @moduledoc """
    Additional metadata to include at the end of a span.
    """

    defstruct [
      :status,
      :result
    ]

    @type t :: %__MODULE__{
            status: :success | :error,
            result: any()
          }

    @doc """
    Create a new SpanResult struct.
    """
    @spec new(any()) :: t()
    def new(result) do
      # Infer a success or error status from the result of the wrapped
      # function. We default to calling any response a `success`.
      status =
        case result do
          :error -> :error
          {:error, _} -> :error
          _ -> :success
        end

      %__MODULE__{status: status, result: result}
    end
  end

  alias OneAndDone.Telemetry

  @namespace :one_and_done

  @doc """
  Measure the duration of a function call.
  """
  @spec span(atom() | list(atom()), map(), fun()) :: any()
  def span(base_name, meta \\ %{}, fun) do
    meta = meta_with_tags(meta)

    base_name
    |> build_name()
    |> :telemetry.span(meta, fn ->
      result = fun.()

      {
        result,
        Map.put(meta, :result, Telemetry.SpanResult.new(result))
      }
    end)
  end

  @doc """
  Emit a telemetry event.
  """
  @spec event(atom() | list(atom()), map(), map()) :: :ok
  def event(base_name, metrics, meta \\ %{}) do
    meta = meta_with_tags(meta)

    base_name
    |> build_name()
    |> :telemetry.execute(metrics, meta)
  end

  defp build_name(paths) when is_list(paths), do: [@namespace | paths]
  defp build_name(path) when is_atom(path), do: [@namespace, path]

  # Ensure the event metadata always has a `tags` entry
  defp meta_with_tags(meta), do: Map.merge(%{tags: []}, meta)
end
