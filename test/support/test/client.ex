defmodule Test.Client do
  use GenServer

  defstruct [
    :gun,
    :gun_process_monitor,
    :gun_stream_ref,
    :caller_ref,
    reply_buffer: []
  ]

  def start, do: GenServer.start(__MODULE__, [])
  def start_link, do: GenServer.start_link(__MODULE__, [])

  def close(pid) do
    :ok = GenServer.call(pid, :close)
    GenServer.stop(pid, :normal)
  end

  def get_replies(pid), do: GenServer.call(pid, :get_replies)
  def push(pid, message), do: GenServer.call(pid, {:push, message})

  def init(_args) do
    host = to_charlist(Test.Site.host())
    port = Test.Site.port()
    path = Test.Site.Endpoint.socket()

    with {:ok, gun_pid} <- :gun.open(host, port),
         {:ok, _protocol} <- :gun.await_up(gun_pid, :timer.seconds(5)),
         stream_ref <- :gun.ws_upgrade(gun_pid, path),
         :ok <- wait_for_upgrade() do
      ref = Process.monitor(gun_pid)

      {:ok,
       __struct__(
         gun: gun_pid,
         gun_process_monitor: ref,
         gun_stream_ref: stream_ref
       )}
    end
  end

  def handle_call(:get_replies, caller_ref, %{caller_ref: nil} = state) do
    if state.reply_buffer == [] do
      {:noreply, %{state | caller_ref: caller_ref}}
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
    warn("Process went down: #{inspect(pid)}")
    {:stop, reason, state}
  end

  def handle_info({:gun_error, _pid, _stream_ref, reason}, state) do
    {:stop, reason, state}
  end

  def handle_info({:gun_ws, _pid, _stream_ref, {:text, payload}}, %{caller_ref: ref} = state)
      when not is_nil(ref) do
    message = Jason.decode!(payload)
    GenServer.reply(ref, {:ok, [message]})
    {:noreply, %{state | caller_ref: nil}}
  end

  def handle_info({:gun_ws, _pid, _stream_ref, {:text, payload}}, state) do
    message = Jason.decode!(payload)
    {:noreply, %{state | reply_buffer: [message | state.reply_buffer]}}
  end

  def handle_info(msg, state) do
    warn("message: #{inspect(msg)}")
    {:noreply, state}
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

  defp warn(msg), do: IO.warn("[client@#{inspect(self())}] #{msg}")
end
