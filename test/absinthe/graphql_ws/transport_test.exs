defmodule Absinthe.GraphqlWS.TransportTest do
  use ExUnit.Case, async: true

  alias Absinthe.GraphqlWS.{Socket, Transport}

  defmodule BadCodeSocket do
    use Absinthe.GraphqlWS.Socket, schema: Test.Site.Schema
    @impl Absinthe.GraphqlWS.Socket
    def handle_init(_payload, socket), do: {:close, {5000, "nope"}, socket}
  end

  defmodule LongReasonSocket do
    use Absinthe.GraphqlWS.Socket, schema: Test.Site.Schema
    @impl Absinthe.GraphqlWS.Socket
    def handle_init(_payload, socket), do: {:close, {4403, String.duplicate("x", 124)}, socket}
  end

  defmodule InvalidUtf8Socket do
    use Absinthe.GraphqlWS.Socket, schema: Test.Site.Schema
    @impl Absinthe.GraphqlWS.Socket
    def handle_init(_payload, socket), do: {:close, {4403, <<0xFF, 0xFE>>}, socket}
  end

  defmodule OkSocket do
    use Absinthe.GraphqlWS.Socket, schema: Test.Site.Schema
    @impl Absinthe.GraphqlWS.Socket
    def handle_init(_payload, socket), do: {:close, {4403, "Forbidden"}, socket}
  end

  defp socket(handler) do
    %Socket{
      absinthe: %{opts: [context: %{}]},
      assigns: %{},
      connect_info: %{},
      endpoint: Test.Site.Endpoint,
      handler: handler,
      keepalive: 0,
      pubsub: nil
    }
  end

  @connection_init %{"type" => "connection_init"}

  describe "handle_inbound/2 connection_init with a {:close, {code, message}, socket} return" do
    test "closes with a valid RFC 6455 code and reason" do
      assert {:reply, :ok, {:close, 4403, "Forbidden"}, %Socket{initialized?: false}} = Transport.handle_inbound(@connection_init, socket(OkSocket))
    end

    test "rejects a close code outside the RFC 6455 sendable range" do
      assert_raise CaseClauseError, fn -> Transport.handle_inbound(@connection_init, socket(BadCodeSocket)) end
    end

    test "rejects a reason longer than 123 bytes" do
      assert_raise CaseClauseError, fn -> Transport.handle_inbound(@connection_init, socket(LongReasonSocket)) end
    end

    test "rejects a reason that is not valid UTF-8" do
      assert_raise ArgumentError, ~r/valid UTF-8/, fn ->
        Transport.handle_inbound(@connection_init, socket(InvalidUtf8Socket))
      end
    end
  end
end
