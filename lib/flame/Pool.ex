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

  alias FLAME

  @retries 3
  @base_delay 500
  @exponential_factor 2
  @default_timeout :timer.seconds(60)
  @valid_opts [
    :retries,
    :base_delay,
    :exponential_factor,
    :fallback_function,
    :caller_pid,
    :timeout
  ]

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
    opts = get_opts(opts)
    func = fn -> FLAME.Pool.call(pool, func, opts) end
    exponential_retry!(func, opts)
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
    # span_ctx = Tracer.start_span("FLAME.Pool.cast (#{inspect(pool)})")

    # Tracer.set_current_span(span_ctx)
    parent_span_context = Ctx.get_current()
    span_ctx = Tracer.current_span_ctx()
    Logger.metadata(span_ctx: span_ctx)

    opts = get_opts(opts)

    Process.spawn(
      fn ->
        Ctx.attach(parent_span_context)
        Tracer.set_current_span(span_ctx)

        Tracer.with_span "FLAME.Pool.cast (#{inspect(pool)})" do
          span_ctx = Tracer.current_span_ctx()
          Logger.metadata(span_ctx: span_ctx)

          func =
            fn ->
              Tracer.set_current_span(span_ctx)

              Tracer.with_span "FLAME.Pool.cast (#{inspect(pool)})" do
                span_ctx = Tracer.current_span_ctx()
                Logger.metadata(span_ctx: span_ctx)

                func.()
              end
            end

          func = fn ->
            FLAME.Pool.call(pool, func, opts)
          end

          exponential_retry!(
            func,
            opts
          )
        end
      end,
      []
    )

    :ok
  end

  defp get_opts(opts) do
    opts = Keyword.validate!(opts, @valid_opts)
    opts = Keyword.put_new(opts, :retries, @retries)
    opts = Keyword.put_new(opts, :base_delay, @base_delay)
    opts = Keyword.put_new(opts, :exponential_factor, @exponential_factor)
    opts = Keyword.put_new(opts, :timeout, @default_timeout)
    opts = Keyword.put_new(opts, :fallback_function, nil)
    opts = Keyword.put_new(opts, :link, true)
    opts
  end

  defp exponential_retry!(func, opts) do
    # Increase by 1 to account for the initial call
    do_retry(func, opts[:retries] + 1, opts[:base_delay], opts)
  end

  defp do_retry(func, 0, _delay, opts) do
    Logger.debug("Trying to run fallback of #{inspect(func)} with args #{inspect(opts)}")

    case opts[:fallback_function] do
      nil ->
        func.()

      fallback when is_function(fallback, 0) ->
        fallback.()

      _ ->
        raise("Fallback is not a function/0")
    end
  end

  defp do_retry(func, retries, delay, opts) do
    exponential_factor = opts[:exponential_factor]

    Logger.debug("Trying to run function #{inspect(func)}")

    try do
      func.()
    rescue
      err ->
        Logger.warning("Retry attempt failed, #{retries} attempts remaining,
           trying after #{delay} ms.
           Error: #{inspect(err)} in #{inspect(__STACKTRACE__)}")

        Process.sleep(delay)

        do_retry(
          func,
          max(0, retries - 1),
          delay * exponential_factor + :rand.uniform(delay),
          opts
        )
    end
  end
end
