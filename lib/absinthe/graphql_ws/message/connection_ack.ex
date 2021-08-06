defmodule Absinthe.GraphqlWS.Message.ConnectionAck do
  @moduledoc """
  Must be sent in response to a ConnectionInit message from the client.
  """

  alias Absinthe.GraphqlWS.Util

  def new(payload \\ %{}) do
    Util.json_library().encode!(%{type: "connection_ack", payload: payload})
  end
end
