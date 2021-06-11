defmodule Absinthe.GraphqlWS.Message.Pong do
  @moduledoc """
  Reply to a Ping message.
  """

  def new(payload \\ %{}) do
    Jason.encode!(%{type: "pong", payload: payload})
  end
end
