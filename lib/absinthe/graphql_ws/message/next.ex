defmodule Absinthe.GraphqlWS.Message.Next do
  @moduledoc """
  Operation execution result(s) from the source stream created by the binding
  Subscribe message. After all results have been emitted, the Complete message
  will follow indicating stream completion.
  """

  def new(id, payload \\ %{}) do
    Jason.encode!(%{id: id, type: "next", payload: payload})
  end
end
