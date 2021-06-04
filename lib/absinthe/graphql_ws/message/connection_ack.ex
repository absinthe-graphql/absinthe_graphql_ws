defmodule Absinthe.GraphqlWS.Message.ConnectionAck do
  @moduledoc """
  Must be sent in response to a ConnectionInit message from the client.
  """

  def new(payload \\ %{}) do
    Jason.encode!(%{type: "connection_ack", payload: payload})
  end
end
