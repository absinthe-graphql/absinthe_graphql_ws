defmodule Absinthe.GraphqlWS.Util do
  @moduledoc """
  Helper functions that are imported into a module using `Absinthe.GraphqlWS.Socket`.
  """

  alias Absinthe.GraphqlWS.Socket

  @doc """
  Implementation copied from `Phoenix.Socket`, but changed to match on a `Absinthe.GraphqlWS.Socket` struct.
  """
  @spec assign(Socket.t(), atom(), term()) :: Socket.t()
  @spec assign(Socket.t(), map() | keyword()) :: Socket.t()
  def assign(%Socket{} = socket, key, value),
    do: assign(socket, [{key, value}])

  def assign(%Socket{} = socket, attrs) when is_map(attrs) or is_list(attrs),
    do: %{socket | assigns: Map.merge(socket.assigns, Map.new(attrs))}
end
