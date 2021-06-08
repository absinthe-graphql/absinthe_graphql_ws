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
          keepalive: integer(),
          subscriptions: map()
        }

  @typedoc """
  Opcode atoms for messages handled by `handle_control/2`. Used by server-side keepalive messages.
  """
  @type control() ::
          :ping
          | :pong

  @typedoc """
  Opcode atoms for messages returned by `handle_in/2`.
  """
  @type opcode() ::
          :text
          | :binary
          | control()

  @typedoc """
  Valid replies from `Absinthe.GraphqlWS.Transport.handle_in/2`
  """
  @type reply() ::
          {:ok, t()}
          | {:reply, :ok, {opcode(), term()}, t()}
          | {:reply, :error, {opcode(), term()}, t()}
          | {:stop, term(), t()}

  @typedoc """
  Valid replies from `c:handle_message/2`
  """
  @type response() ::
          {:ok, t()}
          | {:push, {opcode(), term()}, t()}
          | {:stop, term(), t()}

  @doc """
  Handles messages that are sent to this process through `send/2`, which have not been caught
  by the default implementation.


  ## Example

      def handle_message({:thing, thing}, socket) do
        {:ok, assign(socket, :thing, thing)}
      end

      def handle_message(_msg, socket) do
        {:ok, socket}
      end
  """
  @callback handle_message(params :: term(), t()) :: Socket.response()

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
  expects a child spec that starts a process; we do so with a noop Task.
  """
  def __child_spec__(_module, _opts, _socket_opts) do
    %{id: Task, start: {Task, :start_link, [fn -> :ok end]}, restart: :transient}
  end

  @doc """
  When a client connects to this websocket, this function is called to initialize the socket.
  """
  @spec __connect__(module(), map(), Keyword.t()) :: {:ok, Socket.t()}
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
end
