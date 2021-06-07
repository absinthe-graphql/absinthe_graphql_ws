defmodule Absinthe.GraphqlWS.SocketTest do
  use ExUnit.Case

  defp setup_client(_context) do
    assert {:ok, client} = Test.Client.start()
    on_exit(fn -> Test.Client.close(client) end)
    [client: client]
  end

  def send_connection_init(%{client: client}) do
    :ok = Test.Client.push(client, %{type: "connection_init"})
    assert {:ok, [%{"type" => "connection_ack"}]} = Test.Client.get_replies(client)
    :ok
  end

  describe "initalization" do
    test "starts and stops" do
      assert {:ok, client} = Test.Client.start()
      Test.Client.close(client)
    end
  end

  describe "on ConnectionInit" do
    test "replies with ConnectionAck" do
      assert {:ok, client} = Test.Client.start()
      :ok = Test.Client.push(client, %{type: "connection_init"})

      assert {:ok, replies} = Test.Client.get_replies(client)

      assert replies == [
               %{
                 "payload" => %{},
                 "type" => "connection_ack"
               }
             ]
    end
  end

  describe "on Subscribe with a query" do
    setup [:setup_client, :send_connection_init]

    test "passes the query to Absinthe and responds with Next + Complete", %{client: client} do
      id = "simple query"

      query = """
      query {
        things {
          name
        }
      }
      """

      :ok = Test.Client.push(client, %{id: id, type: "subscribe", payload: %{query: query}})

      assert {:ok,
              [
                %{
                  "payload" => %{
                    "data" => %{
                      "things" => [
                        %{"name" => "one"},
                        %{"name" => "two"}
                      ]
                    }
                  },
                  "type" => "next",
                  "id" => ^id
                }
              ]} = Test.Client.get_replies(client)

      assert {:ok,
              [
                %{
                  "payload" => %{},
                  "type" => "complete",
                  "id" => ^id
                }
              ]} = Test.Client.get_replies(client)
    end
  end

  describe "on Subscribe with a mutation" do
    setup [:setup_client, :send_connection_init]

    test "passes variables to Absinthe", %{client: client} do
      id = "mutation-with-variables"

      :ok =
        Test.Client.push(client, %{
          id: id,
          type: "subscribe",
          payload: %{
            query: """
            mutation ChangeThing($id: Integer! $name: String!) {
              change_thing(id: $id, name: $name) {
                id
                name
              }
            }
            """,
            variables: %{id: 1, name: "another one"}
          }
        })

      assert {:ok,
              [
                %{
                  "payload" => %{
                    "data" => %{
                      "change_thing" => %{"id" => 1, "name" => "another one"}
                    }
                  },
                  "type" => "next",
                  "id" => ^id
                }
              ]} = Test.Client.get_replies(client)

      assert {:ok,
              [
                %{
                  "payload" => %{},
                  "type" => "complete",
                  "id" => ^id
                }
              ]} = Test.Client.get_replies(client)
    end
  end
end
