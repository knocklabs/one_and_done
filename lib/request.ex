defmodule OneAndDone.Response do
  @moduledoc """
  A basic module for capturing the essence of a response.
  """

  defstruct [
    :status,
    :body,
    :cookies,
    :headers
  ]

  @spec from_conn(Plug.Conn.t()) :: %__MODULE__{}
  def from_conn(%Plug.Conn{} = conn) do
    %__MODULE__{
      status: conn.status,
      body: conn.resp_body,
      cookies: conn.resp_cookies,
      headers: conn.resp_headers
    }
  end
end
