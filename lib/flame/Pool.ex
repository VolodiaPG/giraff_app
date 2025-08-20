defmodule FLAMERetry do
  @moduledoc """
  A wrapper module for FLAME pool operations that provides a simplified interface
  for making calls to FLAME pools.

  Intercepts the error raised by FLAME when a checkout fails; when the pool fails to spawn a new runner in the pool to serve the call.

  Always fallback mode can be set by setting the :always_fallback Application env
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  require OpenTelemetry.Ctx, as: Ctx

  @retries 2
  @base_delay 50
  @exponential_factor 2
  @timeout :timer.seconds(10)
  # @valid_opts [
  #   :retries,
  #   :base_delay,
  #   :exponential_factor,
  #   :fallback_function,
  #   :caller_pid,
  #   :timeout,
  #   :otel_span
  # ]

  defstruct parent_span_ctx: nil,
            span_ctx: nil,
            fallback_function: nil,
            base_delay: @base_delay,
            retries: @retries,
            exponential_factor: @exponential_factor,
            timeout: @timeout

  @doc """
  Makes a synchronous call to a FLAME pool with the given function and options.

  ## Parameters
    * `pool` - The FLAME pool to call
    * `func` - The function to execute in the pool
    * `opts` - Optional keyword list of options to pass to FLAME.

  ## Options
    * Any other options supported by FLAME.call

  ## Examples
      FLAME.Pool.call(MyPool, fn -> do_work() end)
      FLAME.Pool.call(MyPool, fn -> do_work() end, link: false)
  """

  @spec call(atom(), (-> any()), keyword()) :: any()
  def call(pool, func, opts \\ []) when is_atom(pool) and is_function(func) do
    state = get_opts!(opts)
    state = %{state | span_ctx: Tracer.start_span("FLAME.Pool.cast (#{inspect(pool)})...")}

    Tracer.set_current_span(state.span_ctx)
    Logger.metadata(span_ctx: state.span_ctx)

    func =
      fn ->
        Tracer.set_current_span(state.span_ctx)

        Tracer.with_span "...FLAME.Pool.cast (#{inspect(pool)})" do
          Logger.metadata(span_ctx: Tracer.current_span_ctx())
          func.()
        end
      end

    func = fn ->
      FLAME.Pool.call(pool, func, opts)
      Tracer.end_span(state.span_ctx)
    end

    exponential_retry!(
      func,
      state
    )
  end

  @doc """
  Makes an asynchronous cast to a FLAME pool with the given function and options.

  ## Parameters
    * `pool` - The FLAME pool to cast to
    * `func` - The function to execute in the pool
    * `opts` - Optional keyword list of options to pass to FLAME.

  ## Options
    * Any other options supported by FLAME.cast

  ## Examples
      FLAME.Pool.cast(MyPool, fn -> do_work() end)
      FLAME.Pool.cast(MyPool, fn -> do_work() end, link: true)
  """

  @spec cast(atom(), (-> any()), keyword()) :: :ok
  def cast(pool, func, opts \\ []) when is_atom(pool) and is_function(func) do
    Logger.debug("casting to pool #{inspect(pool)} with func #{inspect(func)} and opts #{inspect(opts)}")
    state = get_opts!(opts)
    state = %{state | span_ctx: Tracer.start_span("FLAME.Pool.cast (#{inspect(pool)})...")}
    parent = self()

    pid =
      Process.spawn(
        fn ->
          Tracer.set_current_span(state.span_ctx)
          Logger.metadata(span_ctx: state.span_ctx)

          func =
            fn ->
              Tracer.set_current_span(state.span_ctx)

              Tracer.with_span "...FLAME.Pool.cast (#{inspect(pool)})" do
                Logger.metadata(span_ctx: Tracer.current_span_ctx())
                func.()
              end
            end

          func = fn ->
            FLAME.Pool.call(pool, func, opts)
            Tracer.end_span(state.span_ctx)
          end

          case res =
                 exponential_retry!(
                   func,
                   state
                 ) do
            {:ok, new_pid} when is_pid(new_pid) ->
              Logger.debug("Successfully spawned a new pid: #{inspect(new_pid)}")
              send(parent, {:ok_finished_spawned_pid, self(), new_pid})
              res

            _ ->
              res
          end
        end,
        []
      )

    {:ok, pid}
  end

  defp get_opts!(opts) do
    opts = Keyword.put_new(opts, :retries, @retries)
    opts = Keyword.put_new(opts, :base_delay, @base_delay)
    opts = Keyword.put_new(opts, :exponential_factor, @exponential_factor)
    opts = Keyword.put_new(opts, :timeout, @timeout)
    opts = Keyword.put_new(opts, :fallback_function, nil)
    opts = Keyword.put_new(opts, :link, true)
    opts = Keyword.put_new(opts, :parent_span_ctx, Tracer.current_span_ctx())

    struct(__MODULE__, opts)
  end

  defp exponential_retry!(func, state) do
    if Application.get_env(:giraff, :always_fallback) do
      Logger.warn("Always fallback mode enabled, running fallback")
      do_retry(func, 0, 0, state)
    else
      # Increase by 1 to account for the initial call
      do_retry(func, state.retries + 1, state.base_delay, state)
    end
  end

  defp do_retry(func, 0, _delay, state) do
    Tracer.end_span(state.span_ctx)
    Tracer.set_current_span(state.parent_span_ctx)

    case state.fallback_function do
      nil ->
        try do
          func.()
        catch
          _ ->
            Logger.error(
              "Fallback function is nil, ran function after already #{state.retries} retries (the max), and failed"
            )

            Process.exit(self(), {:error, {:failed_to_run_function, "Function was
      configured to fail after #{state.retries} retries"}})
        end

      fallback when is_function(fallback, 0) ->
        fallback.()

      _ ->
        raise("Fallback is not a function/0")
    end
  end

  defp do_retry(func, retries, delay, state) do
    Tracer.set_attribute("retries_left", retries)

    try do
      func.()
    catch
      _, %FLAME.Pool.Error{reason: {{:error, {:cost, :degraded}}, _}} ->
        Logger.warning("Cost module instructed to degrade")

        do_retry(
          func,
          0,
          0,
          state
        )

      _, %FLAME.Pool.Error{reason: {{:error, {:cost, :wait}}, _}} ->
        Logger.warning("Cost module instructed to wait, #{retries} retries remaining")

        Process.sleep(delay)

        do_retry(
          func,
          max(0, retries - 1),
          delay * state.exponential_factor + :rand.uniform(delay),
          state
        )

      _, %FLAME.Pool.Error{reason: {{:error, {:cost, {:wait, :no_decrement}}}, _}} ->
        Logger.warning("Cost module instructed to wait, staying at #{retries} retries remaining")

        Process.sleep(delay)

        do_retry(
          func,
          retries,
          delay * state.exponential_factor + :rand.uniform(delay),
          state
        )

      _, err = %FLAME.Pool.Error{} ->
        Logger.warning("Retry attempt failed, #{retries} attempts remaining")

        # Logger.warning("#{inspect(err)} Retry attempt failed, #{retries} attempts remaining,
        #       trying after #{delay} ms.
        #       Error: #{inspect(err)} in #{inspect(__STACKTRACE__)}")

        Process.sleep(delay)

        do_retry(
          func,
          max(0, retries - 1),
          delay * state.exponential_factor + :rand.uniform(delay),
          state
        )
    end
  end
end
