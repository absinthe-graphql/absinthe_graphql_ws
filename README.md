# AbsintheGraphqlWS

Adds a websocket transport for the [GraphQL over WebSocket
Protocol](https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md) to Absinthe running in
Phoenix.

See the [hex docs](https://hexdocs.pm/absinthe_graphql_ws) for more information.

## References

- https://github.com/enisdenjo/graphql-ws
- This project is heavily inspired by [subscriptions-transport-ws](https://github.com/maartenvanvliet/subscriptions-transport-ws)

## Installation

Add `absinthe_graphql_ws` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:absinthe_graphql_ws, "~> 0.3"}
  ]
end
```

## Usage

### Using the websocket client

```elixir
defmodule ExampleWeb.ApiClient do
  use GenServer

  alias Absinthe.GraphqlWS.Client

  def start(endpoint) do
    Client.start(endpoint)
  end

  def init(args) do
    {:ok, args}
  end

  def stop(client) do
    Client.close(client)
  end

  @gql """
  mutation ChangeSomething($id: String!) {
    changeSomething(id: $id) {
      id
      name
    }
  }
  """
  def change_something(client, thing_id) do
    {:ok, body} = Client.query(client, @gql, id: thing_id)

    case get_in(body, ~w[data changeSomething]) do
      nil -> {:error, get_in(body, ~w[errors])}
      thing -> {:ok, thing}
    end
  end

  @gql """
  query GetSomething($id: UUID!) {
    thing(id: $id) {
      id
      name
    }
  }
  """
  def get_thing(client, thing_id) do
    case Client.query(client, @gql, id: thing_id) do
      {:ok, %{"data" => %{"thing" => nil}}} ->
        nil

      {:ok, %{"data" => %{"thing" => result}}} ->
        {:ok, result}

      {:ok, errors} when is_list(errors) ->
        nil
    end
  end

  @gql """
  subscription ThingChanges($thingId: String!){
    thingChanges(thingId: $projectId) {
      id
      name
    }
  }
  """
  # handler is a pid for a process that implements `handle_info/4` as below
  def thing_changes(client, thing_id: thing_id, handler: handler) do
    Client.subscribe(client, @gql, %{thingId: thing_id}, handler)
  end
end
```

An example of handle_info

```elixir
  @impl true
  def handle_info({:subscription, _id, %{"data" => %{"thingChanges" => thing_changes}}}, %{assigns: %{thing: thing}} = socket) do
    changes = thing_changes |> Enum.find(&(&1["id"] == thing.id))
    socket |> do_cool_update(changes["things"]) |> noreply()
  end
```

## Benchmarks

Benchmarks live in the `benchmarks` directory, and can be run with `MIX_ENV=bench mix run
benchmarks/<file>`.

## Contributing

- Pull requests that may be rebased are preferrable to merges or squashes.
- Please **do not** increment the version number in pull requests.

<!-- testing -->