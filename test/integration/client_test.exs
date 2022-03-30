defmodule Absinthe.GraphqlWS.ClientTest do
  # cannot run asynchronously because it makes http requests to the API
  use ExUnit.Case
  alias Absinthe.GraphqlWS.Client

  defmodule FakeTransport do
    def ws_send(_pid, _message) do
    end

    def close(_pid) do
      :ok
    end
  end

  defmodule FakeMonitor do
    def demonitor(_pid) do
    end
  end

  setup do
    [caller_pid: 222, gun_pid: 111]
  end

  describe "start" do
    test "it initializes the connection" do
      {:ok, client} = Client.start(Test.Site.socket_url())
      state = :sys.get_state(client)
      %{gun: _pid} = state
      %{gun_process_monitor: _ref} = state
      %{gun_stream_ref: _stream_ref} = state
      %{monitor: Process} = state
      %{queries: %{}} = state
      %{listeners: %{}} = state
      %{transport: :gun} = state
      assert :ok = Client.close(client)
    end

    test "returns an error on multiple connection_init" do
      {:ok, client} = Client.start(Test.Site.socket_url())
      ref = Process.monitor(client)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, 4429, "Too many initialisation requests"} = Client.push(client, %{type: "connection_init", payload: %{}})
        assert_receive({:DOWN, ^ref, :process, _object, :server_closed})
      end)
    end
  end

  describe "handle_call" do
    test "push connection init stores the caller with key connection_init", %{caller_pid: caller_pid, gun_pid: gun_pid} do
      {:noreply, state} =
        Client.handle_call({:push, %{type: "connection_init"}}, caller_pid, %{queries: %{}, listeners: %{}, gun: gun_pid, transport: FakeTransport})

      assert(state.queries == %{"connection_init" => caller_pid})
      assert(state.gun == gun_pid)
    end

    test "push message with id stores the caller on the id", %{caller_pid: caller_pid, gun_pid: gun_pid} do
      message_id = "bapbapaloobaabapbamboo"

      {:noreply, state} = Client.handle_call({:push, %{id: message_id}}, caller_pid, %{queries: %{}, gun: gun_pid, transport: FakeTransport})
      assert(state.queries == %{message_id => caller_pid})
      assert(state.gun == gun_pid)
    end

    test "sending close", %{caller_pid: caller_pid, gun_pid: gun_pid} do
      state = %{gun_process_monitor: 333, gun: gun_pid, transport: FakeTransport, monitor: FakeMonitor}
      assert {:reply, :ok, ^state} = Client.handle_call(:close, caller_pid, state)
    end
  end

  describe "handle_info" do
    setup do
      [state: %{"fake-state" => "tastes-great"}]
    end

    test "DOWN stops the server", %{caller_pid: caller_pid, state: state} do
      assert {:stop, "end-of-test", ^state} = Client.handle_info({:DOWN, "fake-ref", :process, caller_pid, "end-of-test"}, state)
    end

    test "gun_error stops the server", %{caller_pid: caller_pid, state: state} do
      assert {:stop, "end-of-test", ^state} = Client.handle_info({:gun_error, caller_pid, "stream-ref", "end-of-test"}, state)
    end

    test "gun_ws handles completed requests and removes them from the query map", %{caller_pid: caller_pid} do
      payload = Jason.encode!(%{id: "easy-message-id", type: "complete"})
      state = %{queries: %{"easy-message-id" => 500, "other-message-id" => 501}, listeners: %{}}

      assert(
        {:noreply, %{queries: %{"other-message-id" => 501}, listeners: %{}}} =
          Client.handle_info({:gun_ws, caller_pid, "stream-ref", {:text, payload}}, state)
      )
    end

    test "gun_ws handles completed subscription feeds and removes them from the listeners map", %{caller_pid: caller_pid} do
      payload = Jason.encode!(%{id: "easy-message-id", type: "complete"})
      state = %{listeners: %{"easy-message-id" => 500, "other-message-id" => 501}, queries: %{}}

      assert(
        {:noreply, %{queries: %{}, listeners: %{"other-message-id" => 501}}} =
          Client.handle_info({:gun_ws, caller_pid, "stream-ref", {:text, payload}}, state)
      )
    end

    test "gun_ws forwards requested info to the process named in the query map", %{caller_pid: caller_pid} do
      message = %{"id" => "easy-message-id", "type" => "next", "data" => "foo"}
      state = %{listeners: %{}, queries: %{"easy-message-id" => {self(), :tag}, "other-message-id" => 501}}

      assert({:noreply, ^state} = Client.handle_info({:gun_ws, caller_pid, "stream-ref", {:text, Jason.encode!(message)}}, state))

      assert_received({:tag, {:ok, ^message}})
    end

    test "gun_ws forwards requested info to the subscribers named in the listeners map", %{caller_pid: caller_pid} do
      message = %{"id" => "easy-message-id", "type" => "next", "payload" => "foo"}

      state = %{
        listeners: %{"easy-message-id" => self(), "other-message-id" => 222},
        queries: %{"easy-message-id" => {self(), :tag}, "other-message-id" => 501}
      }

      assert({:noreply, ^state} = Client.handle_info({:gun_ws, caller_pid, "stream-ref", {:text, Jason.encode!(message)}}, state))

      assert_received({:subscription, "easy-message-id", "foo"})
    end

    test "gun_ws forwards connection_ack to the process requesting connection_init", %{caller_pid: caller_pid} do
      message = %{"type" => "connection_ack"}
      state = %{queries: %{"connection_init" => {self(), :tag}, "other-message-id" => 501}, listeners: %{}}

      assert(
        {:noreply, %{queries: %{"other-message-id" => 501}, listeners: %{}}} =
          Client.handle_info({:gun_ws, caller_pid, "stream-ref", {:text, Jason.encode!(message)}}, state)
      )

      assert_received({:tag, {:ok, ^message}})
    end
  end

  describe "query" do
    setup do
      {:ok, client} = Client.start(Test.Site.socket_url())
      [client: client]
    end

    @gql """
    query {
      things {
        id
        name
      }
    }
    """
    test "it returns the data you asked for", %{client: client} do
      assert({:ok, %{"data" => %{"things" => [%{"id" => 1, "name" => "one"}, %{"id" => 2, "name" => "two"}]}}} = Client.query(client, @gql))
    end

    @gql """
    mutation ChangeThing($id: Int! $name: String!) {
      change_thing(id: $id, name: $name) {
        id
        name
      }
    }
    """
    test "it returns errors when there is a problem", %{client: client} do
      assert {:ok,
              [
                %{"locations" => [%{"column" => 16, "line" => 2}], "message" => "In argument \"id\": Expected type \"Int!\", found null."},
                %{"locations" => [%{"column" => 25, "line" => 2}], "message" => "In argument \"name\": Expected type \"String!\", found null."},
                %{"locations" => [%{"column" => 22, "line" => 1}], "message" => "Variable \"id\": Expected non-null, found null."},
                %{"locations" => [%{"column" => 32, "line" => 1}], "message" => "Variable \"name\": Expected non-null, found null."}
              ]} = Client.query(client, @gql)
    end
  end
end
