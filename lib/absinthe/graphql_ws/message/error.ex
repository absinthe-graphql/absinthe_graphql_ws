defmodule Absinthe.GraphqlWS.Message.Error do
  @moduledoc """
  Operation execution error(s) triggered by the Next message happening before
  the actual execution, usually due to validation errors.
  """

  def new(id, payload \\ %{}) do
    Jason.encode!(%{id: id, type: "error", payload: payload})
  end
end
