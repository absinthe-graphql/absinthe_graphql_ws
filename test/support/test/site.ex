defmodule Test.Site do
  @moduledoc false

  @host "localhost"
  @port 29_876
  def host, do: @host
  def port, do: @port

  defmodule GraphSocket do
    use Absinthe.GraphqlWS.Socket, schema: Test.Site.Schema

    @impl Absinthe.GraphqlWS.Socket
    def handle_message({:subscription, params}, socket) do
      Test.Site.TestPubSub.notify(:handle_message_callback, {:subscription, params})
      {:ok, socket}
    end
  end

  defmodule Resolvers do
    @thing_one %{id: 1, name: "one"}
    @thing_two %{id: 2, name: "two"}

    def change_thing(_, %{id: 1, name: name}, _) do
      {:ok, %{id: 1, name: name}}
    end

    def changes_subscription(changes, subscription_params, _) do
      {:ok, changes |> Map.merge(subscription_params)}
    end

    def get_thing(_, %{name: "one"}, _), do: {:ok, @thing_one}
    def get_thing(_, %{name: "two"}, _), do: {:ok, @thing_two}

    def handle_messages(_, _, _), do: {:ok, true}

    def list_things(_, _, _) do
      things = [
        @thing_one,
        @thing_two
      ]

      {:ok, things}
    end
  end

  defmodule Schema do
    use Absinthe.Schema

    object :thing do
      field(:id, non_null(:integer))
      field(:name, non_null(:string))
    end

    query do
      field :things, list_of(:thing) do
        resolve(&Resolvers.list_things/3)
      end

      field :thing, :thing do
        arg(:name, non_null(:string))
        resolve(&Resolvers.get_thing/3)
      end
    end

    mutation do
      field :change_thing, :thing do
        arg(:id, non_null(:integer))
        arg(:name, non_null(:string))
        resolve(&Resolvers.change_thing/3)
      end
    end

    subscription do
      field :thing_changes, :thing do
        arg(:id, non_null(:integer))

        config(fn %{id: id}, _resolver ->
          {:ok, topic: to_string(id)}
        end)

        resolve(&Resolvers.changes_subscription/3)
      end

      field :handle_error, :thing do
        config(fn _, _ ->
          {:error, "subscribe error"}
        end)
      end

      field :handle_message, :boolean do
        arg(:subscription_param, :string)

        config(fn params, _resolver ->
          send(self(), {:subscription, params})
          {:ok, topic: "handle_messages"}
        end)

        resolve(&Resolvers.handle_messages/3)
      end
    end
  end

  defmodule Application do
    @moduledoc false
    use Elixir.Application

    def start(_type, _args) do
      children = [
        {Phoenix.PubSub, name: pubsub_name()},
        Test.Site.Endpoint,
        {Absinthe.Subscription, Test.Site.Endpoint}
      ]

      opts = [strategy: :one_for_one, name: Test.Site.Supervisor]
      Supervisor.start_link(children, opts)
    end

    defp pubsub_name,
      do:
        Elixir.Application.get_env(:absinthe_graphql_ws, Test.Site.Endpoint)
        |> Keyword.fetch!(:pubsub_server)
  end

  defmodule Web do
    @moduledoc false
    def router do
      quote do
        use Phoenix.Router

        import Plug.Conn
        import Phoenix.Controller
      end
    end

    defmacro __using__(which) when is_atom(which) do
      apply(__MODULE__, which, [])
    end
  end

  defmodule TestPubSub do
    @moduledoc false
    def start_link, do: Registry.start_link(keys: :duplicate, name: __MODULE__)

    def subscribe(subscriber_key), do: Registry.register(__MODULE__, subscriber_key, nil)

    def notify(subscriber_key, message) do
      __MODULE__
      |> Registry.lookup(subscriber_key)
      |> Enum.map(fn {pid, _value} -> pid end)
      |> Enum.each(&send(&1, message))
    end
  end

  defmodule Router do
    @moduledoc false
    use Web, :router

    @dialyzer {:nowarn_function, {:call, 2}}

    pipeline :browser do
      plug(:accepts, ["html"])
      plug(:fetch_session)
      plug(:protect_from_forgery)
    end

    scope "/" do
      pipe_through(:browser)
    end
  end

  defmodule Endpoint do
    @moduledoc false
    use Phoenix.Endpoint, otp_app: :absinthe_graphql_ws
    use Absinthe.Phoenix.Endpoint

    @socket "/graphql"
    def socket, do: @socket

    socket @socket,
           Test.Site.GraphSocket,
           websocket: [
             connect_info: [:peer_data, :trace_context_headers, :x_headers, :uri, :user_agent],
             path: "",
             subprotocols: ["graphql-transport-ws"]
           ]

    plug(Plug.Head)
    plug(Test.Site.Router)

    @doc false
    def init(:supervisor, config) do
      {
        :ok,
        Keyword.merge(
          config,
          debug_errors: false,
          http: [
            port: Test.Site.port()
          ],
          https: false,
          secret_key_base: String.duplicate("abcdefgh", 8),
          server: true,
          url: [host: Test.Site.host()]
        )
      }
    end
  end

  def socket_url, do: Router.Helpers.url(Endpoint) |> URI.merge("/graphql") |> URI.to_string()
end
