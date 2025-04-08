defmodule FlameRetryTest do
  use ExUnit.Case
  doctest FLAMERetry

  require Logger

  setup_all do
    counter = start_supervised!({FLAME.FailBackend.Counter, initial_value: 0, name: :counter})

    pid =
      start_supervised!(
        {FLAME.Pool,
         name: Giraff.Fail,
         backend: {FLAME.FailBackend, fail_after_counter: counter},
         min: 0,
         max: 1,
         max_concurrency: 10}
      )

    %{pool: pid, fail_after: counter}
  end

  test "flame retry working" do
    ExUnit.CaptureLog.capture_log(fn ->
      caller_pid = self()

      FLAMERetry.cast(
        Giraff.EndGameBackend,
        fn ->
          Process.sleep(:timer.seconds(1))
          send(caller_pid, {caller_pid, :ok})
        end,
        caller_pid: caller_pid
      )

      assert_receive {^caller_pid, :ok}, :timer.seconds(2)
    end)
  end

  test "flame retry working process" do
    ExUnit.CaptureLog.capture_log(fn ->
      caller_pid = self()

      FLAMERetry.cast(
        Giraff.EndGameBackend,
        fn ->
          Process.spawn(
            fn ->
              Process.sleep(:timer.seconds(1))
              send(caller_pid, {caller_pid, :ok})
            end,
            []
          )
        end,
        caller_pid: caller_pid
      )

      assert_receive {^caller_pid, :ok}, :timer.seconds(2)
    end)
  end

  test "flame retry function exiting" do
    ExUnit.CaptureLog.capture_log(fn ->
      Process.flag(:trap_exit, true)
      caller_pid = self()

      FLAMERetry.cast(
        Giraff.EndGameBackend,
        fn ->
          exit("Simulated error")
        end,
        caller_pid: caller_pid,
        fallback_function: fn ->
          :ok
        end
      )

      assert_receive {:EXIT, _, "Simulated error"}
    end)
  end

  test "flame retry function raising" do
    ExUnit.CaptureLog.capture_log(fn ->
      Process.flag(:trap_exit, true)
      caller_pid = self()

      FLAMERetry.cast(
        Giraff.EndGameBackend,
        fn ->
          raise "Simulated error"
        end,
        caller_pid: caller_pid,
        fallback_function: fn ->
          :ok
        end
      )

      assert_receive {:EXIT, _, {%RuntimeError{message: "Simulated error"}, _stack}}
    end)
  end

  test "flame retry function fallback" do
    ExUnit.CaptureLog.capture_log(fn ->
      # Process.flag(:trap_exit, true)
      caller_pid = self()

      FLAMERetry.cast(
        Giraff.Fail,
        fn ->
          :ok
        end,
        caller_pid: caller_pid,
        retries: 0,
        fallback_function: fn ->
          send(caller_pid, {caller_pid, :ok})
          Logger.debug("FLAMERetryTest: calling fallback")
        end
      )

      assert_receive {^caller_pid, :ok}, :timer.seconds(3)
    end)
  end

  describe "tests requiring fail after 1 try backend" do
    setup do
      fail_after =
        start_supervised!({FLAME.FailBackend.Counter, initial_value: 1, name: :failafter})

      pool =
        start_supervised!(
          {FLAME.Pool,
           name: Giraff.FailAfter1,
           backend: {FLAME.FailBackend, fail_after_counter: fail_after},
           min: 0,
           max: 10,
           single_use: false,
           max_concurrency: 1}
        )

      %{pool: pool, fail_after: fail_after}
    end

    test "flame retry function fallback, fails after second" do
      ExUnit.CaptureLog.capture_log(fn ->
        caller_pid = self()

        retry = fn ->
          FLAMERetry.cast(
            Giraff.FailAfter1,
            fn ->
              send(caller_pid, {caller_pid, :ok_nominal, self()})
              # Keep this instance busy to make sure we remote boot a new one
              receive do
                :stop -> :ok
              end
            end,
            caller_pid: caller_pid,
            retries: 0,
            fallback_function: fn ->
              send(caller_pid, {caller_pid, :ok_fallback})
            end
          )
        end

        retry.()

        pid =
          receive do
            {^caller_pid, :ok_nominal, pid} when is_pid(pid) -> pid
          after
            500 ->
              raise "Timeout"
          end

        retry.()
        assert_receive {^caller_pid, :ok_fallback}, :timer.seconds(1)
        send(pid, :stop)
      end)
    end

    test "flame retry function fallback, fails after second, but continue with a
      success ?",
         %{fail_after: fail_after_counter} do
      ExUnit.CaptureLog.capture_log(fn ->
        caller_pid = self()

        retry = fn ->
          FLAMERetry.cast(
            Giraff.FailAfter1,
            fn ->
              Logger.debug("FLAMERetryTest: calling fail_after1")
              send(caller_pid, {caller_pid, :ok_nominal, self()})
              # Keep this instance busy to make sure we remote boot a new one
              receive do
                :stop -> :ok
              end
            end,
            caller_pid: caller_pid,
            retries: 0,
            fallback_function: fn ->
              Logger.debug("FLAMERetryTest: calling fallback")
              send(caller_pid, {caller_pid, :ok_fallback})
            end
          )
        end

        retry.()

        pid =
          receive do
            {^caller_pid, :ok_nominal, pid} when is_pid(pid) -> pid
          after
            500 ->
              raise "Timeout"
          end

        retry.()
        assert_receive {^caller_pid, :ok_fallback}, :timer.seconds(10)

        GenServer.call(fail_after_counter, {:set, 1})
        send(pid, :stop)

        retry.()
        assert_receive {^caller_pid, :ok_nominal, _}, :timer.seconds(10)
      end)
    end

    test "flame retry function fallback, fails after first, but continue with a
      success since second should be ok",
         %{fail_after: fail_after_counter} do
      ExUnit.CaptureLog.capture_log(fn ->
        caller_pid = self()

        GenServer.call(fail_after_counter, {:set, 0})

        retry = fn ->
          FLAMERetry.cast(
            Giraff.FailAfter1,
            fn ->
              Logger.debug("FLAMERetryTest: calling fail_after1")
              send(caller_pid, {caller_pid, :ok_nominal, self()})

              receive do
                :stop -> :ok
              end
            end,
            caller_pid: caller_pid,
            retries: 0,
            fallback_function: fn ->
              Logger.debug("FLAMERetryTest: calling fallback")
              send(caller_pid, {caller_pid, :ok_fallback})
            end
          )
        end

        retry.()

        assert_receive {^caller_pid, :ok_fallback}, :timer.seconds(1)

        GenServer.call(fail_after_counter, {:set, 1})

        retry.()
        assert_receive {^caller_pid, :ok_nominal, receiver}, :timer.seconds(3)

        GenServer.call(fail_after_counter, {:set, 1})

        retry.()
        assert_receive {^caller_pid, :ok_nominal, _}, :timer.seconds(3)

        send(receiver, :stop)

        retry.()
        assert_receive {^caller_pid, :ok_nominal, _}, :timer.seconds(3)
      end)
    end

    test "flame success, but fails after and keeps submitting jobs",
         %{fail_after: fail_after_counter} do
      ExUnit.CaptureLog.capture_log(fn ->
        caller_pid = self()

        GenServer.call(fail_after_counter, {:set, 1})

        retry = fn ->
          FLAMERetry.cast(
            Giraff.FailAfter1,
            fn ->
              Logger.debug("FLAMERetryTest: calling fail_after1")
              send(caller_pid, {caller_pid, :ok_nominal, self()})

              receive do
                :stop -> :ok
              end
            end,
            caller_pid: caller_pid,
            retries: 0,
            fallback_function: fn ->
              Logger.debug("FLAMERetryTest: calling fallback")
              send(caller_pid, {caller_pid, :ok_fallback})
            end
          )
        end

        retry.()
        assert_receive {^caller_pid, :ok_nominal, _}, :timer.seconds(3)

        retry.()
        assert_receive {^caller_pid, :ok_fallback}, :timer.seconds(3)

        retry.()
        assert_receive {^caller_pid, :ok_fallback}, :timer.seconds(3)

        retry.()
        assert_receive {^caller_pid, :ok_fallback}, :timer.seconds(3)
      end)
    end
  end

  describe "tests requiring fail after 1 try backend x2" do
    setup do
      fail_after =
        start_supervised!({FLAME.FailBackend.Counter, name: :failafter_one, initial_value: 2},
          id: :failafter_one
        )

      fail_after2 =
        start_supervised!({FLAME.FailBackend.Counter, name: :failafter_two, initial_value: 2},
          id: :failafter_two
        )

      pool =
        start_supervised!(
          {FLAME.Pool,
           name: Giraff.FailAfter1,
           backend: {FLAME.FailBackend, fail_after_counter: fail_after},
           min: 0,
           max: 10,
           single_use: false,
           max_concurrency: 1}
        )

      pool2 =
        start_supervised!(
          {FLAME.Pool,
           name: Giraff.FailAfter2,
           backend: {FLAME.FailBackend, fail_after_counter: fail_after2},
           min: 0,
           max: 10,
           single_use: false,
           max_concurrency: 1}
        )

      %{pool: pool, pool2: pool2, fail_after: fail_after, fail_after2: fail_after2}
    end

    test "flame success, start a job from within",
         %{fail_after: fail_after_counter} do
      ExUnit.CaptureLog.capture_log(fn ->
        caller_pid = self()

        GenServer.call(fail_after_counter, {:set, 1})

        retry = fn ->
          FLAMERetry.cast(
            Giraff.FailAfter1,
            fn ->
              send(caller_pid, {caller_pid, :ok_nominal, self()})

              FLAMERetry.cast(
                Giraff.FailAfter2,
                fn ->
                  send(caller_pid, {caller_pid, :ok_nominal2, self()})
                end,
                retries: 0,
                caller_pid: caller_pid
              )
            end,
            retries: 0,
            caller_pid: caller_pid
          )
        end

        retry.()
        assert_receive {^caller_pid, :ok_nominal, _}, :timer.seconds(3)
        assert_receive {^caller_pid, :ok_nominal2, _}, :timer.seconds(3)
      end)
    end

    test "flame success, start a job from within, see if first function can
      process a second request in parallel" do
      ExUnit.CaptureLog.capture_log(fn ->
        caller_pid = self()

        retry = fn ->
          FLAMERetry.cast(
            Giraff.FailAfter1,
            fn ->
              send(caller_pid, {caller_pid, :ok_nominal, self()})

              FLAMERetry.cast(
                Giraff.FailAfter2,
                fn ->
                  send(caller_pid, {caller_pid, :ok_nominal2, self()})

                  receive do
                    :stop -> :ok
                  end
                end,
                retries: 0,
                caller_pid: caller_pid,
                fallback_function: fn ->
                  raise "Should not be called 2"
                end
              )
            end,
            retries: 0,
            caller_pid: caller_pid,
            fallback_function: fn ->
              raise "Should not be called 1"
            end
          )
        end

        retry.()
        assert_receive {^caller_pid, :ok_nominal, _}
        assert_receive {^caller_pid, :ok_nominal2, _}

        retry.()
        assert_receive {^caller_pid, :ok_nominal, _}
      end)
    end
  end
end
