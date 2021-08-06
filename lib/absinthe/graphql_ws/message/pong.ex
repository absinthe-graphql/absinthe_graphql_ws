defmodule Absinthe.GraphqlWS.Message.Pong do
  @moduledoc """
  Reply to a Ping message.
  """

  alias Absinthe.GraphqlWS.Util

  def new(payload \\ %{}) do
    Util.json_library().encode!(%{type: "pong", payload: payload})
  end
end
