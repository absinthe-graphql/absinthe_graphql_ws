defmodule Test.Client do
  use GenServer
  require Logger

  defstruct [
    :gun,
    :gun_process_monitor,
    :gun_stream_ref,
    :caller_ref,
    :timeout_ref,
    connected?: false,
    reply_buffer: []
  ]

  def start, do: GenServer.start(__MODULE__, [])
  def start_link, do: GenServer.start_link(__MODULE__, [])

  def close(pid) do
    :ok = GenServer.call(pid, :close)
    GenServer.stop(pid, :normal)
  end

  def connected?(pid), do: GenServer.call(pid, :get_connected)

  def get_new_replies(pid), do: GenServer.call(pid, :get_new_replies, 5000)
  def push(pid, message), do: GenServer.call(pid, {:push, message})

  def init(_args) do
    host = to_charlist(Test.Site.host())
    port = Test.Site.port()
    path = Test.Site.Endpoint.socket()

    with {:ok, gun_pid} <- :gun.open(host, port, %{retry: 0}),
         {:ok, _protocol} <- :gun.await_up(gun_pid, :timer.seconds(5)),
         stream_ref <- :gun.ws_upgrade(gun_pid, path),
         :ok <- wait_for_upgrade() do
      debug("init, gun_pid: #{inspect(gun_pid)}")
      ref = Process.monitor(gun_pid)

      {:ok,
       __struct__(
         connected?: true,
         gun: gun_pid,
         gun_process_monitor: ref,
         gun_stream_ref: stream_ref
       )}
    end
  end

  def handle_call(:get_connected, _from, state), do: {:reply, state.connected?, state}

  def handle_call(:get_new_replies, caller_ref, %{caller_ref: nil} = state) do
    if state.reply_buffer == [] do
      timeout_ref = Process.send_after(self(), :get_replies_timeout, 1000)
      {:noreply, %{state | caller_ref: caller_ref, timeout_ref: timeout_ref}}
    else
      {:reply, {:ok, state.reply_buffer}, %{state | reply_buffer: []}}
    end
  end

  def handle_call({:push, %{} = message}, _from, state) do
    :gun.ws_send(state.gun, {:text, Jason.encode!(message)})
    {:reply, :ok, state}
  end

  def handle_call(:close, _from, state) do
    Process.demonitor(state.gun_process_monitor)
    :ok = :gun.close(state.gun)
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    debug("Process went down: #{inspect(pid)}, #{inspect(reason)}")
    {:noreply, %{state | connected?: false}}
  end

  def handle_info({:gun_error, pid, _stream_ref, reason}, state) do
    debug("gun error: #{inspect(pid)}, #{inspect(reason)}")
    {:stop, reason, state}
  end

  def handle_info({:gun_ws, _pid, _stream_ref, frame}, %{caller_ref: ref, timeout_ref: timeout_ref} = state)
      when not is_nil(ref) and is_reference(timeout_ref) do
    Process.cancel_timer(timeout_ref)
    GenServer.reply(ref, {:ok, [frame | state.reply_buffer]})
    {:noreply, %{state | caller_ref: nil, reply_buffer: [], timeout_ref: nil}}
  end

  def handle_info({:gun_ws, _pid, _stream_ref, frame}, state) do
    {:noreply, %{state | reply_buffer: [frame | state.reply_buffer]}}
  end

  def handle_info({:gun_down, _pid, :ws, :closed, _, _}, state) do
    warn("gun down")
    {:noreply, %{state | connected?: false}}
  end

  def handle_info(:get_replies_timeout, %{caller_ref: ref} = state)
      when not is_nil(ref) do
    debug("get_replies timeout")
    GenServer.reply(ref, {:ok, state.reply_buffer})
    {:noreply, %{state | caller_ref: nil, reply_buffer: [], timeout_ref: nil}}
  end

  def handle_info(msg, state) do
    warn("unhandled handle_info: #{inspect(msg)}")
    {:noreply, state}
  end

  def terminate(reason, _state) do
    debug("terminate: #{inspect(reason)}")
    :ok
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

  defp debug(msg), do: Logger.debug("[client@#{inspect(self())}] #{msg}")
  defp warn(msg), do: Logger.warning("[client@#{inspect(self())}] #{msg}")
end
