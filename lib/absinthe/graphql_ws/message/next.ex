defmodule Absinthe.GraphqlWS.Message.Next do
  @moduledoc """
  Operation execution result(s) from the source stream created by the binding
  Subscribe message. After all results have been emitted, the Complete message
  will follow indicating stream completion.
  """

  alias Absinthe.GraphqlWS.Util

  def new(id, payload \\ %{}) do
    Util.json_library().encode!(%{id: id, type: "next", payload: payload})
  end
end
