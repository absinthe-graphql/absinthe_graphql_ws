defmodule Absinthe.GraphqlWS.Transport do
  @moduledoc """
  Handles messages coming into the socket from clients (implemented in `handle_in/2`)
  as well as messages coming from within Elixir/Absinthe (implemented in `handle_info/2`).

  If the optional `c:Absinthe.GraphqlWS.Socket.handle_message/2` callback is implemented on
  the socket, then messages that are not specifically caught by `handle_info/2` in this
  module will be passed through to `c:Absinthe.GraphqlWS.Socket.handle_message/2`.

  **Note:** This module is not intended for use by individuals integrating this library into
  their codebase, but is documented to help understand the intentions of the code.
  """

  alias Absinthe.GraphqlWS.{Message, Socket, Util}
  alias Phoenix.Socket.Broadcast
  require Logger

  @ping "ping"
  @pong "pong"

  @type control :: Socket.control()
  @type reply_inbound() :: Socket.reply_inbound()
  @type reply_message() :: Socket.reply_message()
  @type socket() :: Socket.t()

  defmacrop debug(msg), do: quote(do: Logger.debug("[graph-socket@#{inspect(self())}] #{unquote(msg)}"))
  defmacrop warn(msg), do: quote(do: Logger.warning("[graph-socket@#{inspect(self())}] #{unquote(msg)}"))

  @doc """
  Generally this will only receive `:pong` messages in response to our keepalive
  ping messages. Client-side websocket libraries handle these control frames
  automatically in order to adhere to the spec, so unless a customer is writing their
  own low-level websocket it should be handled for them.
  """
  @spec handle_control({term(), opcode: control()}, socket()) :: reply_inbound()
  def handle_control({_, opcode: :ping}, socket), do: {:reply, :ok, {:pong, @pong}, socket}

  def handle_control({_, opcode: :pong}, socket) do
    start = socket.assigns[:start]
    measurements = %{duration: System.monotonic_time() - start}
    metadata = %{}
    :telemetry.execute([:absinthe_graphql_ws, :keepalive, :stop], measurements, metadata)
    system_time = System.system_time()
    socket = Util.assign(socket, last_inbound_pong: system_time, last_keepalive: system_time)

    {:ok, socket}
  end

  def handle_control(message, state) do
    warn(" unhandled control frame #{inspect(message)}")
    {:ok, state}
  end

  @doc """
  Receive messages from clients. We expect all incoming messages to be JSON encoded
  text, so if something else comes in we blow up.
  """
  @spec handle_in({binary(), [opcode: :text]}, socket()) :: reply_inbound()
  def handle_in({text, [opcode: :text]}, socket) do
    Util.json_library().decode(text)
    |> case do
      {:ok, json} ->
        handle_inbound(json, socket)

      {:error, reason} ->
        warn("JSON parse error: #{inspect(reason)}")
        {:reply, :error, {:text, Message.Error.new("4400")}, socket}
    end
  end

  @doc """
  Receive messages from inside the house.

  * `:keepalive` - Regularly send messages with opcode of `0x09`, ie `:ping`. The `graphql-ws`
    library has a strong opinion that it does not want to implement client-side keepalive, so
    in order to keep the websocket from closing we need to send it messages.

  * `subscription:data` - After we subscribe to an Absinthe subscription, we may receive messages
    for the relevant subscription. The `graphql-ws` will have sent us an `id` along with the
    subscription query, so we need to map our internal topic back to that `id` in order for the
    client to figure out what to do with our message.

  * `:complete` - If we get a `query` or a `mutation` on the websocket, we're supposed to reply
    with a `Next` message followed by a `Complete` message. We follow through on the latter by
    putting a message on our process queue.

  * fallthrough - If `c:Absinthe.GraphqlWs.Socket.handle_message/2` is defined on the socket,
    then uncaught messages will be sent there.
  """
  @spec handle_info(term(), socket()) :: reply_message()
  def handle_info(:keepalive, socket) do
    Process.send_after(self(), :keepalive, socket.keepalive)
    start = System.monotonic_time()
    measurements = %{system_time: System.system_time()}
    metadata = %{}
    :telemetry.execute([:absinthe_graphql_ws, :keepalive, :start], measurements, metadata)
    system_time = System.system_time()
    socket = Util.assign(socket, start: start, last_outbound_ping: system_time, last_keepalive: system_time)

    {:push, {:ping, @ping}, socket}
  end

  def handle_info(%Broadcast{event: "subscription:data", payload: payload, topic: topic}, socket) do
    subscription_id = socket.subscriptions[topic]
    message = Message.Next.new(subscription_id, payload.result)
    measurements = %{payload_size: byte_size(message)}

    metadata = %{
      platform: get_platform(socket),
      session_id: get_session_id(socket),
      client_app_version: get_client_app_version(socket),
      user_id: get_user_id(socket),
      payload: payload
    }

    :telemetry.execute([:absinthe_graphql_ws, :handle_info, :broadcast], measurements, metadata)

    {:push, {:text, message}, socket}
  end

  def handle_info({:complete, id}, socket) do
    metadata = %{
      platform: get_platform(socket),
      session_id: get_session_id(socket),
      client_app_version: get_client_app_version(socket),
      user_id: get_user_id(socket),
    }

    :telemetry.execute([:absinthe_graphql_ws, :handle_info, :complete], %{}, metadata)

    {:push, {:text, Message.Complete.new(id)}, socket}
  end

  def handle_info(message, socket) do
    if function_exported?(socket.handler, :handle_message, 2) do
      socket.handler.handle_message(message, socket)
    else
      {:ok, socket}
    end
  end

  @doc """
  Process was stopped.
  """
  @spec terminate(term(), socket()) :: :ok
  def terminate(reason, _socket) do
    debug("terminated: #{inspect(reason)}")
    :ok
  end

  @doc """
  Callbacks for parsed JSON payloads coming in from a client.

  See:
  https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md
  """
  @spec handle_inbound(map(), socket()) :: reply_inbound()
  def handle_inbound(%{"type" => "connection_init"}, %{initialized?: true} = socket) do
    metadata = %{
      code: 4429,
      operation: :connection_init,
      reason: :too_many_initialisation_requests,
      platform: get_platform(socket)
    }

    :telemetry.execute([:absinthe_graphql_ws, :handle_inbound, :error], %{}, metadata)

    close(4429, "Too many initialisation requests", socket)
  end

  def handle_inbound(%{"type" => "connection_init"} = message, %{handler: handler} = socket) do
    if function_exported?(handler, :handle_init, 2) do
      case handler.handle_init(Map.get(message, "payload", %{}), socket) do
        {:ok, payload, socket} ->
          {:reply, :ok, {:text, Message.ConnectionAck.new(payload)}, %{socket | initialized?: true}}

        {:error, payload, socket} ->
          {:reply, :ok, {:text, Message.Error.new(payload)}, socket}
      end
    else
      {:reply, :ok, {:text, Message.ConnectionAck.new()}, %{socket | initialized?: true}}
    end
  end

  def handle_inbound(%{"type" => "subscribe"}, %{initialized?: false} = socket) do
    metadata = %{
      code: 4400,
      operation: :subscribe,
      reason: :subscribe_before_connection_init,
      platform: get_platform(socket)
    }

    :telemetry.execute([:absinthe_graphql_ws, :handle_inbound, :error], %{}, metadata)

    close(4400, "Subscribe message received before ConnectionInit", socket)
  end

  def handle_inbound(%{"id" => id, "type" => "subscribe", "payload" => payload}, socket) do
    payload
    |> handle_subscribe(id, socket)
  end

  def handle_inbound(%{"id" => id, "type" => "complete"}, socket) do
    socket.subscriptions
    |> Enum.find_value(fn
      {topic, ^id} ->
        {:ok, topic}

      _ ->
        false
    end)
    |> case do
      {:ok, topic} ->
        debug("unsubscribing from topic #{topic}")
        Phoenix.PubSub.unsubscribe(socket.pubsub, topic)
        Absinthe.Subscription.unsubscribe(socket.endpoint, topic)

        {:ok, %{socket | subscriptions: Map.delete(socket.subscriptions, topic)}}

      _ ->
        {:ok, socket}
    end
  end

  def handle_inbound(%{"type" => "ping"}, socket) do
    system_time = System.system_time()
    message = Message.Pong.new()
    measurements = %{payload_size: byte_size(message)}
    metadata = %{platform: get_platform(socket)}
    :telemetry.execute([:absinthe_graphql_ws, :handle_inbound, :ping], measurements, metadata)

    socket = Util.assign(socket, last_inbound_ping: system_time, last_keepalive: system_time)
    {:reply, :ok, {:text, message}, socket}
  end

  def handle_inbound(msg, socket) do
    warn("unhandled message #{inspect(msg)}")
    close(4400, "Unhandled message from client", socket)
  end

  @doc """
  Subscribe messages in graphql-ws may include a subscription, implying a subscription to
  a long term stream of data. These messages may also be queries or mutations, so do not require
  a stream.
  """
  def handle_subscribe(payload, id, socket) do
    with %{schema: schema} <- socket.absinthe,
         {:ok, variables} <- parse_variables(payload),
         {:ok, query} <- parse_query(payload) do
      opts = socket.absinthe.opts |> Keyword.merge(variables: variables)

      Absinthe.Logger.log_run(:debug, {
        query,
        schema,
        [],
        opts
      })

      run_doc(socket, id, query, socket.absinthe, opts)
    else
      _ ->
        {:ok, socket}
    end
  end

  defp close(code, message, socket) do
    {:reply, :ok, {:close, code, message}, socket}
  end

  defp parse_query(%{"query" => query}) when is_binary(query), do: {:ok, query}
  defp parse_query(_), do: {:ok, ""}

  defp parse_variables(%{"variables" => variables}) when is_map(variables), do: {:ok, variables}
  defp parse_variables(_), do: {:ok, %{}}

  def pipeline(schema, options) do
    schema
    |> Absinthe.Pipeline.for_document(options)
  end

  defp run_doc(socket, id, query, config, opts) do
    case run(query, config[:schema], config[:pipeline], opts) do
      {:ok, %{"subscribed" => topic}, context} ->
        debug("subscribed to topic #{topic}")

        :ok =
          Phoenix.PubSub.subscribe(
            socket.pubsub,
            topic,
            # metadata: {:fastlane, self(), @serializer, []},
            link: true
          )

        socket = merge_opts(socket, context: context)
        {:ok, %{socket | subscriptions: Map.put(socket.subscriptions, topic, id)}}

      {:ok, %{data: _} = reply, context} ->
        queue_complete_message(id)
        socket = merge_opts(socket, context: context)
        {:reply, :ok, {:text, Message.Next.new(id, reply)}, socket}

      {:ok, %{errors: errors}, context} ->
        socket = merge_opts(socket, context: context)
        {:reply, :ok, {:text, Message.Error.new(id, errors)}, socket}

      {:error, reply} ->
        {:reply, :error, {:text, Message.Error.new(id, reply)}, socket}
    end
  end

  defp run(document, schema, pipeline, options) do
    {module, fun} = pipeline

    case Absinthe.Pipeline.run(document, apply(module, fun, [schema, options])) do
      {:ok, %{result: result, execution: res}, _phases} ->
        {:ok, result, res.context}

      {:error, msg, _phases} ->
        {:error, msg}
    end
  end

  defp merge_opts(socket, opts) do
    %{socket | absinthe: %{socket.absinthe | opts: opts}}
  end

  defp queue_complete_message(id), do: send(self(), {:complete, id})

  defp get_platform(socket), do: socket.assigns[:platform] || "unknown"

  defp get_session_id(socket), do: socket.assigns[:session_id]

  defp get_client_app_version(socket), do: socket.assigns[:client_app_version]

  defp get_user_id(socket), do: socket.assigns[:user_id]
end
