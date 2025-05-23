defmodule CostTest do
  use ExUnit.Case
  doctest Giraff.Cost

  require Logger

  setup_all do
    pidcost = start_supervised!({Giraff.Cost, name: CostForTesting})

    %{pidcost: pidcost}
  end

  test "scaling without prior interactions", %{pidcost: pidcost} do
    parent = self()

    start_supervised!({
      FLAME.Pool,
      name: Giraff.CostTestBackend,
      backend: {
        FLAME.CostTestBackend,
        name: :cost_test_backend,
        price: 100,
        on_accepted_offer: fn arg ->
          Giraff.Cost.on_accepted_offer(pidcost, arg)
          send(parent, :ok)
        end,
        on_new_boot: fn arg ->
          Giraff.Cost.on_new_boot(pidcost, arg)
        end
      },
      min: 0,
      max: 1,
      max_concurrency: 10
    })

    FLAME.Pool.call(Giraff.CostTestBackend, fn ->
      :ok
    end)

    assert_receive :ok
  end

  test "scaling with prior interactions", %{pidcost: pidcost} do
    start_supervised!({
      FLAME.Pool,
      name: Giraff.CostTestBackend,
      backend: {
        FLAME.CostTestBackend,
        name: :cost_test_backend,
        price: 100,
        on_accepted_offer: fn arg ->
          Giraff.Cost.on_accepted_offer(pidcost, arg)
        end,
        on_new_boot: fn arg ->
          Giraff.Cost.on_new_boot(pidcost, arg)
        end
      },
      min: 0,
      max: 10,
      max_concurrency: 1
    })

    FLAME.Pool.call(Giraff.CostTestBackend, fn ->
      assert_raise(RuntimeError, fn ->
        FLAME.Pool.call(Giraff.CostTestBackend, fn ->
          Logger.debug("called twice")
        end)
      end)
    end)
  end

  test "scaling with prior interactions and a failsafe pool for fallback", %{pidcost: pidcost} do
    start_supervised!({
      FLAME.Pool,
      name: Giraff.CostTestBackend,
      backend: {
        FLAME.CostTestBackend,
        name: :cost_test_backend,
        price: 100,
        on_accepted_offer: fn arg ->
          Giraff.Cost.on_accepted_offer(pidcost, arg)
        end,
        on_new_boot: fn arg ->
          Giraff.Cost.on_new_boot(pidcost, arg)
        end
      },
      min: 0,
      max: 10,
      max_concurrency: 1
    })

    FLAMERetry.call(Giraff.CostTestBackend, fn ->
      FLAMERetry.call(
        Giraff.CostTestBackend,
        fn ->
          Logger.debug("called twice")
        end,
        retries: 0,
        fallback_function: fn ->
          :ok
        end
      )
    end)
  end
end
