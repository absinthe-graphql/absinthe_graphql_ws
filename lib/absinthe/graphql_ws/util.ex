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

  @doc """
  Adds key-value pairs into Absinthe context. This can be used in the `c:Absinthe.GraphqlWS.Socket.handle_init/2`
  to assign keys/values to the current Absinthe context.

  ## Examples

      defmodule MySocket do
        use Absinthe.GraphqlWS.Socket, schema: MySchema

        def handle_init(%{"user_id" => user_id}) do
          user = find_user(user_id)
          socket = assign_context(socket, current_user: user)
          %{:reply, :ok, {:text, Absinthe.GraphqlWS.Message.ConnectionAck.new()}, socket}
        end
      end
  """
  def assign_context(%Socket{absinthe: absinthe} = socket, context) do
    context =
      absinthe
      |> Map.fetch!(:opts)
      |> Keyword.fetch!(:context)
      |> Map.merge(Map.new(context))

    put_options(socket, context: context)
  end

  @doc """
  Same as `assign_context/2` except one key-value pair is assigned.
  """
  def assign_context(socket, key, value) do
    assign_context(socket, [{key, value}])
  end

  @doc """
  Sets the options for a given GraphQL document execution.

  ## Examples

      iex> put_options(socket, context: %{current_user: user})
      %Socket{}
  """
  def put_options(socket, opts) do
    opts = Keyword.merge(socket.absinthe.opts, opts)
    absinthe = %{socket.absinthe | opts: opts}
    %{socket | absinthe: absinthe}
  end

  @doc """
  Retrieves the JSON library module used to encode and decode transport messages
  """
  def json_library, do: Application.get_env(:absinthe_graphql_ws, :json_library)
end
