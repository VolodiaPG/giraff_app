defmodule FlameRetryTest do
  use ExUnit.Case
  doctest FlameRetry

  setup_all do
    Application.ensure_all_started(:flame_retry)
  end

  test "greets the world" do
    assert FlameRetry.hello() == :world
  end
end
