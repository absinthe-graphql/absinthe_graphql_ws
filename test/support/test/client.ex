defmodule Test.Client do
  use GenServer

  defstruct [
    :gun,
    :gun_ref
  ]

  def start(), do: GenServer.start(__MODULE__, [])
  def start_link(), do: GenServer.start_link(__MODULE__, [])

  def close(pid) do
    :ok = GenServer.call(pid, :close)
    GenServer.stop(pid, :normal)
  end

  def push(pid, message), do: GenServer.call(pid, {:push, message})

  def init(_args) do
    host = to_charlist(Test.Site.host())
    port = Test.Site.port()

    with {:ok, gun_pid} <- :gun.open(host, port),
         {:ok, _protocol} <- :gun.await_up(gun_pid, :timer.seconds(5)),
         _ref <- :gun.ws_upgrade(gun_pid, Test.Site.Endpoint.socket()),
         ref = Process.monitor(gun_pid) do
      {:ok, __struct__(gun: gun_pid, gun_ref: ref)}
    end
  end

  def handle_call(:close, _from, state) do
    Process.demonitor(state.gun_ref)
    :ok = :gun.close(state.gun)
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    warn("Process went down: #{inspect(pid)}")
    {:stop, reason, state}
  end

  def handle_info(msg, state) do
    warn("message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp warn(msg), do: IO.warn("[client@#{inspect(self())}] #{msg}")
end
