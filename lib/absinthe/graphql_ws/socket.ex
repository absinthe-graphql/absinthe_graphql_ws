defmodule Absinthe.GraphqlWS.Socket do
  @moduledoc """
  GraphQL over WebSocket protocol:
  https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md

  Notes on WebSockets and `Phoenix.Socket.Transport`:
  * Data comes in and goes out in frames. These frames have an `opcode`.
  * When `opcode` is `:text` or `:binary`, the message is routed to the `handle_in` callback.
  * When `opcode` is `:ping` or `:pong`, the message is routed to the `handle_control` callback.

  https://github.com/theturtle32/WebSocket-Node/blob/a2cd3065167668a9685db0d5f9c4083e8a1839f0/docs/WebSocketFrame.md
  """

  alias Absinthe.GraphqlWS.Socket

  @default_keepalive 30_000

  @typedoc """
  Options that must be passed in:

  * `schema` - required - The Absinthe schema for the current application (example: `MyAppWeb.Schema`)
  * `keepalive` - optional - Interval in milliseconds to send `:ping` control frames over the websocket.
  * `pipeline` - optional - A `{module, function}` tuple defining how to generate an Absinthe pipeline for each incoming message.
    Defaults to `{Absinthe.GraphqlWS.Socket, :absinthe_pipeline}`.
  """
  @enforce_keys ~w[absinthe connect_info endpoint handler keepalive pubsub]a
  defstruct [
    :absinthe,
    :connect_info,
    :endpoint,
    :handler,
    :keepalive,
    :pubsub,
    assigns: %{},
    subscriptions: %{}
  ]

  @type t() :: %Socket{
          absinthe: map(),
          assigns: map(),
          connect_info: map(),
          endpoint: module(),
          keepalive: integer(),
          subscriptions: map()
        }

  @type control() ::
          :ping
          | :pong

  @type opcode() ::
          :text
          | :binary
          | control()

  @type reply() ::
          {:ok, t()}
          | {:reply, :ok, {opcode(), term()}, t()}
          | {:reply, :error, {opcode(), term()}, t()}
          | {:stop, term(), t()}

  @type response() ::
          {:ok, t()}
          | {:push, {opcode(), term()}, t()}
          | {:stop, term(), t()}

  @doc """
  Handles messages that are sent to this process through `send/2`, which have not been caught
  by the default implementation.
  """
  @callback handle_message(params :: map(), t()) :: Socket.response()

  @optional_callbacks handle_message: 2

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

  @doc false
  def new(attrs \\ []), do: __struct__(attrs)

  @doc """
  Provides a stub implementation that allows the socket to start. Phoenix.Socket.Transport
  expects a child spec that starts a process, so we do so with a noop Task.
  """
  def __child_spec__(_module, _opts, _socket_opts) do
    %{id: Task, start: {Task, :start_link, [fn -> :ok end]}, restart: :transient}
  end

  @doc """
  When a client connects to this websocket, this function is called to initialize the socket.
  """
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

    {:ok,
     Socket.new(
       absinthe: absinthe_config,
       connect_info: socket.connect_info,
       endpoint: socket.endpoint,
       handler: module,
       keepalive: keepalive,
       pubsub: pubsub
     )}
  end

  @doc """
  Provides the default absinthe pipeline
  """
  def absinthe_pipeline(schema, options) do
    schema
    |> Absinthe.Pipeline.for_document(options)
  end
end
