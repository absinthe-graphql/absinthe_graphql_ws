# Installation

Add `absinthe_graphql_ws` to deps:

```elixir
def deps do
  [
    {:absinthe, "~> 1.6"},
    {:absinthe_graphql_ws, github: "geometerio/absinthe_graphql_ws"},
    {:jason, "~> 1.2"}, # or compatible JSON library
    {:phoenix, "~> 1.5"}
    # ...
  ]
end
```

## Configuration

`absinthe_graphql_ws` defaults to using [Jason](https://hex.pm/packages/jason) for JSON encoding and
decoding. This can be configured as follows:

```elixir
config :absinthe_graphql_ws, :json_library, MyJSONLibrary
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

#### handle_init/2

A websocket client following the `graphql-ws` protocol will send a `connection_init` message upon
connection. By default, the socket will reply with a `connection_ack` message including an empty
payload.

If `c:Absinthe.GraphqlWS.Socket.handle_init/2` is implemented on the socket, then it will be called.

#### handle_message/2

If the socket process will receive custom messages from within the application, then the
`c:Absinthe.GraphqlWS.Socket.handle_message/2` optional callback can be defined to handle these:

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

If a message is sent to the socket via `send/2` (or another mechanism triggering
`c:Phoenix.Socket.Transport.handle_info/2`), and is not caught by the `graphql-ws` specific
handlers, and `c:Absinthe.GraphqlWS.Socket.handle_message/2` is implemented on the socket, then the
message is passed through to the callback.
