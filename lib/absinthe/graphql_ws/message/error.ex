defmodule Absinthe.GraphqlWS.Message.Error do
  @moduledoc """
  Operation execution error(s) triggered by the Next message happening before
  the actual execution, usually due to validation errors.
  """

  alias Absinthe.GraphqlWS.Util

  def new(id, payload \\ %{}) do
    Util.json_library().encode!(%{id: id, type: "error", payload: payload})
  end
end
