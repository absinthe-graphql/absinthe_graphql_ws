# AbsintheGraphqlWS

Adds a websocket transport for the
[GraphQL over WebSocket Protocol](https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md)
to Absinthe running in Phoenix.

## References

* https://github.com/enisdenjo/graphql-ws
* This project is heavily inspired by [subscriptions-transport-ws](https://github.com/maartenvanvliet/subscriptions-transport-ws)

## Installation

Add `absinthe_graphql_ws` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:absinthe_graphql_ws, github: "geometerio/absinteh_graphql_ws"}
  ]
end
```
