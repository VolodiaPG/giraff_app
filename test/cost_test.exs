defmodule CostTest do
  use ExUnit.Case
  doctest Giraff.Cost

  require Logger

  test "scaling without prior interactions" do
    ExUnit.CaptureLog.capture_log(fn ->
      pidcost = start_supervised!({Giraff.Cost, name: CostForTesting})
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
        max_concurrency: 1
      })

      FLAME.Pool.call(Giraff.CostTestBackend, fn ->
        :ok
      end)

      assert_receive :ok
    end)
  end

  test "scaling with prior interactions" do
    ExUnit.CaptureLog.capture_log(fn ->
      pidcost = start_supervised!({Giraff.Cost, name: CostForTesting})

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

      caught =
        FLAME.Pool.call(Giraff.CostTestBackend, fn ->
          try do
            FLAME.Pool.call(Giraff.CostTestBackend, fn ->
              assert false == true
            end)
          rescue
            e in FLAME.Pool.Error ->
              e
          end
        end)

      {{:error, reason}, _} = caught.reason
      assert reason == {:cost, :degraded}
    end)
  end

  test "scaling with prior interactions and a failsafe pool for fallback" do
    ExUnit.CaptureLog.capture_log(fn ->
      pidcost = start_supervised!({Giraff.Cost, name: CostForTesting})

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

      parent = self()

      FLAMERetry.cast(Giraff.CostTestBackend, fn ->
        FLAMERetry.call(
          Giraff.CostTestBackend,
          fn ->
            Logger.debug("called twice")
          end,
          retries: 3,
          fallback_function: fn ->
            :ok

            send(parent, :ok)
          end
        )
      end)

      assert_receive :ok, 100
    end)
  end

  test "in_flight > max, thus should scale up" do
    ExUnit.CaptureLog.capture_log(fn ->
      pidcost = start_supervised!({Giraff.Cost, name: CostForTesting, nb_requests_to_wait: 1})

      start_supervised!({
        FLAME.Pool,
        name: Giraff.CostTestBackend,
        backend: {
          FLAME.CostTestBackend,
          name: :cost_test_backend,
          price: 0,
          on_accepted_offer: fn arg ->
            Giraff.Cost.on_accepted_offer(pidcost, arg)
          end,
          on_new_boot: fn arg ->
            Giraff.Cost.on_new_boot(pidcost, arg)
          end
        },
        min: 0,
        max: 19,
        max_concurrency: 1
      })

      parent = self()

      Giraff.Cost.on_new_request_start(pidcost)

      FLAMERetry.cast(Giraff.CostTestBackend, fn ->
        send(parent, {self(), :ok})

        receive do
          :ok ->
            :ok
        end
      end)

      pid =
        receive do
          {pid, :ok} -> pid
        end

      Giraff.Cost.on_new_request_start(pidcost)

      FLAMERetry.cast(Giraff.CostTestBackend, fn ->
        send(parent, {self(), :ok})
      end)

      refute_receive {_, :ok}, 200

      Giraff.Cost.on_new_request_end(pidcost)

      send(pid, :ok)

      {_, :ok} =
        receive do
          {pid2, :ok} when pid2 != pid -> {pid2, :ok}
        after
          1000 ->
            raise("Did not receive :ok, timeout")
        end
    end)
  end
end
