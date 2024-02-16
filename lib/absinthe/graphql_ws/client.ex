defmodule Absinthe.GraphqlWS.Client do
  use GenServer
  alias Absinthe.GraphqlWS.Uuid
  require Logger

  defstruct [
    :gun,
    :gun_process_monitor,
    :gun_stream_ref,
    :monitor,
    :transport,
    listeners: %{},
    queries: %{}
  ]

  def start(endpoint, init_payload \\ %{}) do
    {:ok, client} = GenServer.start(__MODULE__, endpoint: endpoint)
    {:ok, %{"type" => "connection_ack"}} = push(client, %{type: "connection_init", payload: init_payload})
    {:ok, client}
  end

  def init(endpoint: endpoint) do
    init(endpoint: endpoint, monitor: Process, transport: :gun)
  end

  def init(endpoint: endpoint, monitor: monitor, transport: transport) do
    uri = URI.parse(endpoint)

    with {:ok, gun_pid} <- transport.open(uri.host |> to_charlist(), uri.port, %{protocols: [:http]}),
         {:ok, _protocol} <- transport.await_up(gun_pid, :timer.seconds(5)),
         stream_ref <- transport.ws_upgrade(gun_pid, uri.path),
         :ok <- wait_for_upgrade() do
      ref = monitor.monitor(gun_pid)

      {:ok,
       __struct__(
         gun: gun_pid,
         gun_process_monitor: ref,
         gun_stream_ref: stream_ref,
         monitor: monitor,
         transport: transport
       )}
    end
  end

  def close(pid) do
    :ok = GenServer.call(pid, :close)
    GenServer.stop(pid, :normal)
  end

  def handle_call({:push, %{type: "connection_init"} = message}, from, state) do
    send_and_cache("connection_init", from, message, state)
  end

  def handle_call({:push, %{id: id} = message}, from, state) do
    send_and_cache(id, from, message, state)
  end

  def handle_call({:query, gql, variables}, from, state) do
    id = Uuid.generate()

    send_and_cache(id, from, make_message(id, gql, variables), state)
  end

  def handle_call(:close, _from, state) do
    state.monitor.demonitor(state.gun_process_monitor)
    :ok = state.transport.close(state.gun)
    {:reply, :ok, state}
  end

  def handle_call({:subscribe, gql, variables, handler}, _from, %{listeners: listeners} = state) do
    id = Uuid.generate()

    state.transport.ws_send(state.gun, {:text, Jason.encode!(make_message(id, gql, variables))})
    listeners = Map.put(listeners, id, handler)
    state = Map.put(state, :listeners, listeners)
    {:reply, {:ok, id}, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    warn("Process went down: #{inspect(pid)}")
    {:stop, reason, state}
  end

  def handle_info({:gun_error, _pid, _stream_ref, reason}, state) do
    {:stop, reason, state}
  end

  def handle_info({:gun_ws, _pid, _stream_ref, {:text, payload}}, state) do
    message = Jason.decode!(payload)

    new_listeners =
      case message do
        %{"id" => id, "type" => "complete"} ->
          state.listeners |> Map.delete(id)

        _ ->
          state.listeners
      end

    new_queries =
      case message do
        %{"id" => id, "type" => "complete"} ->
          state.queries |> Map.delete(id)

        %{"id" => id} ->
          # IO.inspect(message, label: "INBOUND")
          dispatch(id, message, state)

        %{"type" => "connection_ack"} ->
          ref = Map.fetch!(state.queries, "connection_init")
          GenServer.reply(ref, {:ok, message})
          state.queries |> Map.delete("connection_init")

        _ ->
          state.queries
      end

    {:noreply, %{state | queries: new_queries, listeners: new_listeners}}
  end

  def handle_info({:gun_ws, _pid, _stream_ref, {:close, code, payload}}, state) do
    Map.values(state.queries)
    |> Enum.each(fn ref -> GenServer.reply(ref, {:error, code, payload}) end)

    {:stop, :server_closed, %{state | queries: %{}}}
  end

  def handle_info(msg, state) do
    warn("unhandled handle_info: #{inspect(msg)}")
    {:noreply, state}
  end

  defp dispatch(id, message, state) do
    cond do
      Map.has_key?(state.listeners, id) ->
        handler = Map.get(state.listeners, id)
        send(handler, {:subscription, id, message["payload"]})
        # handler.(message)
        state.queries

      Map.has_key?(state.queries, id) ->
        ref = Map.fetch!(state.queries, id)
        GenServer.reply(ref, {:ok, message})
        state.queries
    end
  end

  defp make_message(id, gql, variables) do
    %{
      id: id,
      type: "subscribe",
      payload: %{
        query: gql,
        variables: Map.new(variables)
      }
    }
  end

  def push(pid, message), do: GenServer.call(pid, {:push, message})

  def query(pid, gql, variables \\ %{}) do
    case GenServer.call(pid, {:query, gql, variables}) do
      {:ok, %{"payload" => payload}} -> {:ok, payload}
      result -> result
    end
  end

  defp send_and_cache(id, from, message, %{queries: queries} = state) do
    # IO.inspect(message, label: "OUTBOUND")
    state.transport.ws_send(state.gun, {:text, Jason.encode!(message)})
    queries = Map.put(queries, id, from)
    state = Map.put(state, :queries, queries)
    {:noreply, state}
  end

  def subscribe(pid, gql, variables, handler) do
    case GenServer.call(pid, {:subscribe, gql, variables, handler}) do
      {:ok, %{"id" => id}} -> {:ok, id}
      result -> result
    end
  end

  defp wait_for_upgrade do
    receive do
      {:gun_upgrade, _pid, _stream_ref, ["websocket"], _headers} ->
        :ok

      {:gun_response, _pid, _stream_ref, _, status, _headers} ->
        {:error, status}

      {:gun_error, _pid, _stream_ref, reason} ->
        {:error, reason}
    after
      1000 ->
        exit(:timeout)
    end
  end

  # defp debug(msg), do: Logger.debug("[client@#{inspect(self())}] #{msg}")
  defp warn(msg), do: Logger.warning("[client@#{inspect(self())}] #{msg}")
end
