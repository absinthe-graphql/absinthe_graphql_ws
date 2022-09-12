defmodule Absinthe.GraphqlWS.SocketTest do
  use ExUnit.Case

  defp setup_client(_context) do
    assert {:ok, client} = Test.Client.start()
    on_exit(fn -> Test.Client.close(client) end)
    [client: client]
  end

  def send_connection_init(%{client: client}) do
    :ok = Test.Client.push(client, %{type: "connection_init"})

    assert {:ok,
            [
              {:text, Jason.encode!(%{"type" => "connection_ack", "payload" => %{}})}
            ]} ==
             Test.Client.get_new_replies(client)

    :ok
  end

  def assert_connected(client) do
    assert Test.Client.connected?(client)
  end

  def assert_socket_closed(client, code, payload) do
    assert {:ok, [{:close, ^code, ^payload}]} = Test.Client.get_new_replies(client)

    Test.Retry.retry_for(5000, fn ->
      refute Test.Client.connected?(client)
    end)
  end

  defp assert_json_received(client, payload) do
    assert {:ok, [{:text, json}]} = Test.Client.get_new_replies(client)
    assert json == Jason.encode!(payload)
  end

  describe "initalization" do
    test "starts and stops" do
      assert {:ok, client} = Test.Client.start()
      Test.Client.close(client)
    end
  end

  describe "on ConnectionInit" do
    setup :setup_client

    test "replies with ConnectionAck", %{client: client} do
      :ok = Test.Client.push(client, %{type: "connection_init"})

      assert_json_received(client, %{
        "payload" => %{},
        "type" => "connection_ack"
      })
    end

    test "closes the socket with an error if received multiple times", %{client: client} do
      :ok = Test.Client.push(client, %{type: "connection_init"})
      assert {:ok, [{:text, _}]} = Test.Client.get_new_replies(client)

      assert_connected(client)

      :ok = Test.Client.push(client, %{type: "connection_init"})
      assert_socket_closed(client, 4429, "Too many initialisation requests")
    end
  end

  describe "on Ping" do
    setup [:setup_client, :send_connection_init]

    test "replies with Pong", %{client: client} do
      :ok = Test.Client.push(client, %{type: "ping", payload: %{}})

      assert_json_received(client, %{
        "payload" => %{},
        "type" => "pong"
      })
    end

    test "replies with same payload as Ping", %{client: client} do
      :ok = Test.Client.push(client, %{type: "ping", payload: %{"hello" => "world"}})

      assert_json_received(client, %{
        "payload" => %{"hello" => "world"},
        "type" => "pong"
      })
    end
  end

  describe "on message receipt that does not follow the spec" do
    setup [:setup_client, :send_connection_init]

    test "closes the socket with 4400", %{client: client} do
      :ok = Test.Client.push(client, %{type: "made_up"})
      assert_socket_closed(client, 4400, "Unhandled message from client")
    end
  end

  describe "on Subscribe if ConnectionInit has not been sent" do
    setup :setup_client

    test "closes the socket with 4400", %{client: client} do
      id = "query-before-init"

      query = """
      query {
        things {
          name
        }
      }
      """

      :ok = Test.Client.push(client, %{id: id, type: "subscribe", payload: %{query: query}})
      assert_socket_closed(client, 4400, "Subscribe message received before ConnectionInit")
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

      assert_json_received(client, %{
        "payload" => %{
          "data" => %{
            "things" => [
              %{"name" => "one"},
              %{"name" => "two"}
            ]
          }
        },
        "type" => "next",
        "id" => id
      })

      assert_json_received(client, %{
        "payload" => %{},
        "type" => "complete",
        "id" => id
      })
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
            mutation ChangeThing($id: Int! $name: String!) {
              change_thing(id: $id, name: $name) {
                id
                name
              }
            }
            """,
            variables: %{id: 1, name: "another one"}
          }
        })

      assert_json_received(client, %{
        "payload" => %{
          "data" => %{
            "change_thing" => %{"id" => 1, "name" => "another one"}
          }
        },
        "type" => "next",
        "id" => id
      })

      assert_json_received(client, %{
        "payload" => %{},
        "type" => "complete",
        "id" => id
      })
    end
  end

  describe "on Subscribe with a subscription" do
    setup [:setup_client, :send_connection_init]

    test "pushes Next messages for the subscription topic, as they are published", %{client: client} do
      id = "subscription"

      :ok =
        Test.Client.push(client, %{
          id: id,
          type: "subscribe",
          payload: %{
            query: """
            subscription ThingChanges($id: Int!) {
              thing_changes(id: $id) {
                id
                name
              }
            }
            """,
            variables: %{id: 2}
          }
        })

      assert {:ok, []} = Test.Client.get_new_replies(client)

      Absinthe.Subscription.publish(Test.Site.Endpoint, %{name: "blue"}, thing_changes: "2")

      assert_json_received(client, %{
        "payload" => %{
          "data" => %{"thing_changes" => %{"id" => 2, "name" => "blue"}}
        },
        "type" => "next",
        "id" => id
      })

      Absinthe.Subscription.publish(Test.Site.Endpoint, %{name: "fun"}, thing_changes: "1")

      assert {:ok, []} = Test.Client.get_new_replies(client)
    end

    test "stops a subscription when client sends a Complete", %{client: client} do
      id = "subscription-to-be-cancelled"

      :ok =
        Test.Client.push(client, %{
          id: id,
          type: "subscribe",
          payload: %{
            query: """
            subscription ThingChanges($id: Int!) {
              thing_changes(id: $id) {
                id
                name
              }
            }
            """,
            variables: %{id: 2}
          }
        })

      assert {:ok, []} = Test.Client.get_new_replies(client)
      Absinthe.Subscription.publish(Test.Site.Endpoint, %{name: "blue"}, thing_changes: "2")

      assert_json_received(client, %{
        "payload" => %{
          "data" => %{"thing_changes" => %{"id" => 2, "name" => "blue"}}
        },
        "type" => "next",
        "id" => id
      })

      :ok = Test.Client.push(client, %{id: id, type: "complete"})
      assert {:ok, []} = Test.Client.get_new_replies(client)

      Absinthe.Subscription.publish(Test.Site.Endpoint, %{name: "true"}, thing_changes: "2")
      assert {:ok, []} = Test.Client.get_new_replies(client)
    end

    test "correct error payload for subscription failure", %{client: client} do
      id = "subscription-with-error"

      :ok =
        Test.Client.push(client, %{
          id: id,
          type: "subscribe",
          payload: %{
            query: """
            subscription HandleError {
              handleError {
                id
                name
              }
            }
            """
          }
        })

      assert_json_received(
        client,
        %{
          "id" => "subscription-with-error",
          "payload" => [%{"locations" => [%{"column" => 3, "line" => 2}], "message" => "subscribe error"}],
          "type" => "error"
        }
      )
    end
  end

  describe "handle_message callbacks" do
    setup [:setup_client, :send_connection_init]

    test "are called when the socket receives &handle_info/2 with a message not caught by graphql-ws", %{client: client} do
      id = "handle-message-callback"

      Test.Site.TestPubSub.subscribe(:handle_message_callback)

      :ok =
        Test.Client.push(client, %{
          id: id,
          type: "subscribe",
          payload: %{
            query: """
            subscription HandleMessage($subscriptionParam: String!) {
              handle_message(subscriptionParam: $subscriptionParam)
            }
            """,
            variables: %{subscriptionParam: "boo"}
          }
        })

      assert {:ok, []} = Test.Client.get_new_replies(client)

      assert_receive({:subscription, %{}} = reply)
      assert reply == {:subscription, %{subscription_param: "boo"}}
    end
  end

  describe "handle_ping callbacks" do
    setup [:setup_client, :send_connection_init]

    test "are called when the socket receives a ping", %{client: client} do
      Test.Site.TestPubSub.subscribe(:handle_ping_callback)

      :ok =
        Test.Client.push(client, %{
          type: "ping",
          payload: %{
            foo: "bar"
          }
        })

      assert_receive({:ping, %{}} = reply)
      assert reply == {:ping, %{"foo" => "bar"}}
    end
  end
end
