defmodule Absinthe.GraphqlWS.SocketTest do
  use ExUnit.Case

  describe "initalization" do
    test "starts and stops" do
      assert {:ok, client} = Test.Client.start()
      Test.Client.close(client)
    end
  end

  describe "when receiving ConnectionInit" do
    test "sends ConnectionAck" do
      assert {:ok, client} = Test.Client.start()
      :ok = Test.Client.push(client, %{type: "connection_init"})

      assert {:ok, replies} = Test.Client.get_replies(client)

      assert replies == [
               %{
                 "payload" => %{},
                 "type" => "connection_ack"
               }
             ]

      Test.Client.close(client)
    end
  end
end
