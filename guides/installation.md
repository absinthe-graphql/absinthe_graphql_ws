# Installation

Add `absinthe_graphql_ws` to deps:

```elixir
def deps do
  [
    {:absinthe, "~> 1.6"},
    {:absinthe_graphql_ws, github: "geometerio/absinteh_graphql_ws"},
    {:phoenix, "~> 1.5"}
    # ...
  ]
end
```

## Custom socket

In `lib/my_app_web/channels`, add a new socket:

```elixir
defmodule MyAppWeb.GraphqlWSSocket do
  use Absinthe.GraphqlWS.Socket, schema: MyAppWeb.Schema
end
```

## Phoenix endpoint

Now mount the socket in your Phoenix.Endpoint:

```elixir
socket "/api/graphql-ws", MyAppWeb.GraphqlWSSocket,
  websocket: [path: "", subprotocols: ["graphql-transport-ws"]]
```

## Optional callbacks

If the socket process will receive custom messages from within the application,
then the `c:Absinthe.GraphqlWS.Socket.handle_message/2` optional callback can
be defined to handle these:

```elixir
defmodule MyAppWeb.GraphqlWSSocket do
  use Absinthe.GraphqlWS.Socket, schema: MyAppWeb.Schema

  @impl Absinthe.GraphqlWS.Socket
  def handle_message({:internal_thing, id}, socket) do
    {:ok, assign(socket, :message, id)}
  end

  def handle_message({:external_thing, _id}, socket) do
    {:push, {:text, "{}"}, socket}
  end
end
```