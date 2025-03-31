defmodule FLAMETracing do
  @moduledoc """
  A wrapper module for FLAME pool operations that provides a simplified interface
  for making calls to FLAME pools.

  Intercepts the error raised by FLAME when a checkout fails; when the pool fails to spawn a new runner in the pool to serve the call.

  Always fallback mode can be set by setting the :always_fallback Application env
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  require OpenTelemetry.Ctx, as: Ctx
  alias FLAMERetry, as: FLAME

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
    process_function(&FLAME.call/3, pool, func, opts)
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
    process_function(&FLAME.cast/3, pool, func, opts)
  end

  defp process_function(dispatch_function, pool, func, opts \\ [])
       when is_atom(pool) and is_function(func) do
    span_ctx = Tracer.current_span_ctx()
    parent_span_context = Ctx.get_current()

    func = fn ->
      Ctx.attach(parent_span_context)
      Tracer.set_current_span(span_ctx)
      Logger.metadata(span_ctx: span_ctx)

      Tracer.set_attribute("sla", System.get_env("SLA"))
      func.()
    end

    fallback_function =
      case opts[:fallback_function] do
        nil ->
          nil

        fallback_function ->
          fn ->
            Ctx.attach(parent_span_context)
            Tracer.set_current_span(span_ctx)
            Logger.metadata(span_ctx: span_ctx)

            Tracer.set_attribute("sla", System.get_env("SLA"))
            fallback_function.()
          end
      end

    updated_opts = Keyword.put(opts, :fallback_function, fallback_function)
    dispatch_function.(pool, func, updated_opts)
  end
end
