defmodule Absinthe.GraphqlWS.Transport do
  @moduledoc """
  Handles messages coming into the socket from clients (implemented in `handle_in/2`)
  as well as messages coming from within Elixir/Absinthe (implemented in `handle_info/2`).

  If the optional `c:Absinthe.GraphqlWS.Socket.handle_message/2` callback is implemented on
  the socket, then messages that are not specifically caught by `handle_info/2` in this
  module will be passed through to `c:Absinthe.GraphqlWS.Socket.handle_message/2`.
  """

  alias Absinthe.GraphqlWS.Socket
  alias Phoenix.Socket.Broadcast
  require Logger

  @ping "ping"
  @pong "pong"

  @error Jason.encode!(%{id: "4400", type: "error"})
  @ack Jason.encode!(%{type: "connection_ack"})

  @doc """
  Generally this will only receive `:pong` messages in response to our keepalive
  ping messages. Client-side websocket libraries handle these control frames
  automatically in order to adhere to the spec, so unless a customer is writing their
  own low-level websocket it should be handled for them.
  """
  @spec handle_control({term(), opcode: Socket.control()}, Socket.t()) :: Socket.reply()
  def handle_control({_, opcode: :ping}, socket), do: {:reply, :ok, {:pong, @pong}, socket}
  def handle_control({_, opcode: :pong}, socket), do: {:ok, socket}

  def handle_control(message, state) do
    warn(" unhandled control frame #{inspect(message)}")
    {:ok, state}
  end

  @doc """
  Receive messages from clients. We expect all incoming messages to be JSON encoded
  text, so if something else comes in we blow up.
  """
  @spec handle_in({binary(), [opcode: :text]}, Socket.t()) :: Socket.reply()
  def handle_in({text, [opcode: :text]}, socket) do
    Jason.decode(text)
    |> case do
      {:ok, json} ->
        handle_message(json, socket)

      {:error, reason} ->
        warn("JSON parse error: #{inspect(reason)}")
        {:reply, :error, {:text, @error}, socket}
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

  * fallthrough - If `handle_message/2` is defined on the socket, then uncaught messages will be
    sent
  """
  @spec handle_info(term(), Socket.t()) :: Socket.response()
  def handle_info(:keepalive, socket) do
    Process.send_after(self(), :keepalive, socket.keepalive)
    {:push, {:ping, @ping}, socket}
  end

  def handle_info(%Broadcast{event: "subscription:data", payload: payload, topic: topic}, socket) do
    subscription_id = socket.subscriptions[topic]
    {:push, {:text, next(subscription_id, payload.result)}, socket}
  end

  def handle_info({:complete, id}, socket) do
    {:push, {:text, complete(id)}, socket}
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
  @spec terminate(term(), Socket.t()) :: :ok
  def terminate(reason, _socket) do
    debug("terminated: #{inspect(reason)}")
    :ok
  end

  @doc """
  Callbacks for parsed JSON payloads coming in from a client.

  See:
  https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md
  """
  @spec handle_message(map(), Socket.t()) :: Socket.reply()
  def handle_message(%{"type" => "connection_init"}, socket) do
    {:reply, :ok, {:text, @ack}, socket}
  end

  def handle_message(%{"id" => id, "type" => "subscribe", "payload" => payload}, socket) do
    payload
    |> handle_subscribe(id, socket)
  end

  def handle_message(%{"id" => id, "type" => "complete"}, socket) do
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

        {:ok, %{socket | subscriptions: Map.delete(socket.subscriptions, id)}}

      _ ->
        {:ok, socket}
    end
  end

  def handle_message(msg, socket) do
    warn("unhandled message #{inspect(msg)}")
    {:ok, socket}
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
        queue_complete(id)
        socket = merge_opts(socket, context: context)
        {:reply, :ok, {:text, next(id, reply)}, socket}

      {:ok, %{errors: _} = reply, context} ->
        socket = merge_opts(socket, context: context)
        {:reply, :ok, {:text, error(id, reply)}, socket}

      {:error, reply} ->
        {:reply, :error, {:text, reply}, socket}
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

  defp complete(id), do: Jason.encode!(%{id: id, type: "complete"})
  defp error(id, payload), do: Jason.encode!(%{id: id, type: "error", payload: payload})
  defp next(id, payload), do: Jason.encode!(%{id: id, type: "next", payload: payload})
  defp queue_complete(id), do: send(self(), {:complete, id})

  defp debug(msg), do: Logger.debug("[graph-socket@#{inspect(self())}] #{msg}")
  defp warn(msg), do: Logger.warn("[graph-socket@#{inspect(self())}] #{msg}")
end
