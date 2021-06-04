defmodule AbsintheGraphqlWsTest do
  use ExUnit.Case
  doctest AbsintheGraphqlWs

  test "greets the world" do
    assert AbsintheGraphqlWs.hello() == :world
  end
end
