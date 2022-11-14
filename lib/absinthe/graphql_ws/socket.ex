defmodule Absinthe.GraphqlWS.Socket do
  @moduledoc """
  This module is used by a custom websocket, which can then handle connections from a client
  implementing the [GraphQL over WebSocket protocol](https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md)

  ## Options

  * `schema` - required - The Absinthe schema for the current application (example: `MyAppWeb.Schema`)
  * `keepalive` - optional - Interval in milliseconds to send `:ping` control frames over the websocket.
    Defaults to `30_000` (30 seconds).
  * `pipeline` - optional - A `{module, function}` tuple defining how to generate an Absinthe pipeline
    for each incoming message. Defaults to `{Absinthe.GraphqlWS.Socket, :absinthe_pipeline}`.

  ## Pipeline modification

  The `:pipeline` option to socket definition defaults to `{Absinthe.GraphqlWS.Socket, :absinthe_pipeline}`.
  This function returns the default pipeline provided by `&Absinthe.Pipeline.for_document/2`. Absinthe query execution
  can be modified by altering the list of phases in this pipeline. See `Absinthe.Pipeline` for more info.

  If an alternate pipeline function is provided, it must accept the arguments `schema` and `options`. These
  options include the current context and any variables that are included with the requested query.

  ## Example

      defmodule MyAppWeb.GraphqlSocket do
        use Absinthe.GraphqlWS.Socket, schema: MyAppWeb.Schema

        def handle_message(_msg, socket) do
          {:ok, socket}
        end
      end
  """

  alias Absinthe.GraphqlWS.Socket
  require Logger

  @default_keepalive 30_000

  @enforce_keys ~w[absinthe connect_info endpoint handler keepalive pubsub]a
  defstruct [
    :absinthe,
    :connect_info,
    :endpoint,
    :handler,
    :keepalive,
    :pubsub,
    assigns: %{},
    initialized?: false,
    subscriptions: %{}
  ]

  @typedoc """
  A socket that holds information necessary for parsing incoming messages as well as outgoing subscription data.
  """
  @type t() :: %Socket{
          absinthe: map(),
          assigns: map(),
          connect_info: map(),
          endpoint: module(),
          initialized?: boolean(),
          keepalive: integer(),
          subscriptions: map()
        }
  @type socket() :: t()

  @typedoc """
  Opcode atoms for messages handled by `handle_control/2`. Used by server-side keepalive messages.
  """
  @type control() ::
          :ping
          | :pong

  @typedoc """
  Opcode atoms for messages pushed to the client.
  """
  @type opcode() ::
          :text
          | :binary
          | control()

  @typedoc """
  JSON that conforms to the `graphql-ws` protocol.
  """
  @type message() :: binary()

  @typedoc """
  A websocket frame to send to the client.
  """
  @type frame() :: {opcode(), message()}
  @typedoc """
  Used internally by `Absinthe.GraphqlWS.Transport.handle_in/2`.

  These are return values to incoming messages from a websocket.

  ## Values

  * `{:ok, socket}` - save new socket state, without sending any data to the client.
  * `{:reply, :ok, {:text, "{}"}, socket}` - send JSON content to the client.
  * `{:reply, :error, {:text, "{}"}, socket}` - send an error with JSON payload to the client.
  * `{:stop, :normal, socket}` - shut down the socket process.
  """
  @type reply_inbound() ::
          {:ok, socket()}
          | {:reply, :ok, frame(), socket()}
          | {:reply, :error, frame(), socket()}
          | {:stop, term(), socket()}

  @typedoc """
  Valid return values from `c:handle_message/2`.

  These are return values to messages that have been received from within Elixir

  ## Values

  * `{:ok, socket}` - save new socket state, without sending any data to the client.
  * `{:push, {:text, Message.Next.new(id, %{})}, socket}` - save new socket state, and send data to the client.
  * `{:stop, :reason, socket}` - stop the socket.
  """
  @type reply_message() ::
          {:ok, socket()}
          | {:push, frame(), socket()}
          | {:stop, term(), socket()}

  @typedoc """
  Return values from `c:handle_init/2`.
  """
  @type init() ::
          {:ok, map(), socket()}
          | {:error, map(), socket()}
          | {:stop, term(), socket()}

  @doc """
  Handles messages that are sent to this process through `send/2`, which have not been caught
  by the default implementation. It must return a `t:reply_message/0`.

  If pushing content to the websocket, it must return a tuple in the form
  `{:push, {:text, message}, socket}`, where `message` is JSON that represents a valid `grapql-ws`
  message.

  ## Example

      alias Absinthe.GraphqlWS.Message

      def handle_message({:thing, thing}, socket) do
        {:ok, assign(socket, :thing, thing)}
      end

      def handle_message({:send, id, payload}, socket) do
        {:push, {:text, Message.Next.new(id, payload)}, socket}
      end

      def handle_message(_msg, socket) do
        {:ok, socket}
      end
  """
  @callback handle_message(params :: term(), socket()) :: Socket.reply_message()

  @doc """
  Handle the `connection_init` message sent by the socket implementation. This will receive
  the `payload` from the message, defaulting to an empty map if received from the client.

  This can be used for custom authentication/authorization, using
  `Absinthe.GraphqlWS.Util.assign_context/2` to modify the Absinthe context.

  In case the user is authenticated through session cookies, the session data may be accessed in
  the socket's `:connect_info` field. Note that you need to send a `_csrf_token` param in the URL to effectively receive
  the session info (or else the session will be `nil`). For more information, visit the Phoenix Endpoint docs:
  https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#socket/3-common-configuration

  ## Example

      defmodule MySocket do
        use Absinthe.GraphqlWS.Socket, schema: MySchema

        def handle_init(%{"user_id" => user_id}, socket) do
          case find_user(user_id) do
            nil ->
              {:error, "Forbidden", socket}
            user ->
              socket = assign_context(socket, current_user: user)
              {:ok, %{name: user.name}, socket}
          end
        end
      end
  """
  @callback handle_init(payload :: map(), socket()) :: Socket.init()

  @optional_callbacks handle_message: 2, handle_init: 2

  @spec __after_compile__(any(), any()) :: :ok
  def __after_compile__(env, _bytecode) do
    opts = Module.get_attribute(env.module, :graphql_ws_socket_opts)

    unless Keyword.has_key?(opts, :schema) do
      :elixir_errors.erl_warn(env.line, env.file, "#{env.module} must specify `:schema` when using Absinthe.GraphqlWS.Socket")
    end

    :ok
  end

  defmacro __using__(opts) do
    quote do
      @graphql_ws_socket_opts unquote(opts)
      @after_compile Absinthe.GraphqlWS.Socket

      import Absinthe.GraphqlWS.Util
      alias Absinthe.GraphqlWS.Socket

      @behaviour Phoenix.Socket.Transport
      @behaviour Absinthe.GraphqlWS.Socket

      @doc false
      @impl Phoenix.Socket.Transport
      def child_spec(opts) do
        Socket.__child_spec__(__MODULE__, opts, @graphql_ws_socket_opts)
      end

      @doc false
      @impl Phoenix.Socket.Transport
      def connect(transport) do
        Socket.__connect__(__MODULE__, transport, @graphql_ws_socket_opts)
      end

      @doc false
      @impl Phoenix.Socket.Transport
      def init(socket) do
        if socket.keepalive > 0,
          do: Process.send_after(self(), :keepalive, socket.keepalive)

        {:ok, socket}
      end

      @doc false
      @impl Phoenix.Socket.Transport
      def handle_control(message, socket),
        do: Absinthe.GraphqlWS.Transport.handle_control(message, socket)

      @doc false
      @impl Phoenix.Socket.Transport
      def handle_in(message, socket),
        do: Absinthe.GraphqlWS.Transport.handle_in(message, socket)

      @doc false
      @impl Phoenix.Socket.Transport
      def handle_info(message, socket),
        do: Absinthe.GraphqlWS.Transport.handle_info(message, socket)

      @doc false
      @impl Phoenix.Socket.Transport
      def terminate(message, socket),
        do: Absinthe.GraphqlWS.Transport.terminate(message, socket)

      defoverridable terminate: 2
    end
  end

  defmacrop debug(msg), do: quote(do: Logger.debug("[graph-socket@#{inspect(self())}] #{unquote(msg)}"))

  @doc false
  def new(attrs \\ []), do: __struct__(attrs)

  @doc """
  Provides a stub implementation that allows the socket to start. Phoenix.Socket.Transport
  expects a child spec that starts a process; we do so with a noop Task.
  """
  def __child_spec__(module, _opts, _socket_opts) do
    %{id: {__MODULE__, module}, start: {Task, :start_link, [fn -> :ok end]}, restart: :transient}
  end

  @doc """
  When a client connects to this websocket, this function is called to initialize the socket.
  """
  @spec __connect__(module(), map(), Keyword.t()) :: {:ok, socket()}
  def __connect__(module, socket, options) do
    absinthe_pipeline = Keyword.get(options, :pipeline, {__MODULE__, :absinthe_pipeline})
    pubsub = socket.endpoint.config(:pubsub_server)
    schema = Keyword.fetch!(options, :schema)
    keepalive = Keyword.get(options, :keepalive, @default_keepalive)

    absinthe_config = %{
      opts: [
        context: %{
          pubsub: socket.endpoint
        }
      ],
      pipeline: absinthe_pipeline,
      schema: schema
    }

    socket =
      Socket.new(
        absinthe: absinthe_config,
        connect_info: socket.connect_info,
        endpoint: socket.endpoint,
        handler: module,
        keepalive: keepalive,
        pubsub: pubsub
      )

    debug("connect: #{socket}")

    {:ok, socket}
  end

  @doc """
  Provides the default absinthe pipeline.

  ## Params

  * `schema` - An `Absinthe.Schema.t()`
  * `options` - A keyword list with the current context, variables, etc for the
    current query.
  """
  @spec absinthe_pipeline(Absinthe.Schema.t(), Keyword.t()) :: Absinthe.Pipeline.t()
  def absinthe_pipeline(schema, options) do
    schema
    |> Absinthe.Pipeline.for_document(options)
  end

  defimpl String.Chars do
    def to_string(socket) do
      handler = Module.split(socket.handler) |> Enum.join(".")
      connect_info = Map.keys(socket.connect_info) |> inspect()
      "#Socket<handler=#{handler}, connect_info=#{connect_info}, keepalive=#{keepalive(socket.keepalive)}>"
    end

    defp keepalive(0), do: "disabled"
    defp keepalive(value) when value > 10_000, do: "#{value / 1000}s"
    defp keepalive(value), do: "#{value}ms"
  end
end
