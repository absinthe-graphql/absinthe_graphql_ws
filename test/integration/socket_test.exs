defmodule Absinthe.GraphqlWS.SocketTest do
  use ExUnit.Case

  setup do
    ExUnit.CaptureLog.capture_log(fn -> Test.Site.Application.start(%{}, %{}) end)
    :ok
  end

  describe "interactions" do
    test "starts and stops" do
      assert {:ok, client} = Test.Client.start()
      Test.Client.close(client)
    end
  end
end
