defmodule TheBeaconTest do
  use ExUnit.Case
  doctest TheBeacon

  test "greets the world" do
    assert TheBeacon.hello() == :world
  end
end
