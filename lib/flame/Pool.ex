defmodule FLAMERetry do
  @moduledoc """
  A wrapper module for FLAME pool operations that provides a simplified interface
  for making calls to FLAME pools.

  Intercepts the error raised by FLAME when a checkout fails; when the pool fails to spawn a new runner in the pool to serve the call.
  """

  require Logger
  alias FLAME

  @retries 10
  @base_delay 500
  @exponential_factor 2

  @valid_opts [
    :retries,
    :base_delay,
    :exponential_factor,
    :fallback_function
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
    opts = Keyword.put_new(opts, :link, false)
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
    opts = get_opts(opts)
    opts = Keyword.put_new(opts, :link, false)
    func = fn -> FLAME.Pool.cast(pool, func, opts) end
    exponential_retry!(func, opts)
  end

  defp get_opts(opts) do
    opts = Keyword.validate!(opts, @valid_opts)
    opts = Keyword.put_new(opts, :retries, @retries)
    opts = Keyword.put_new(opts, :base_delay, @base_delay)
    opts = Keyword.put_new(opts, :exponential_factor, @exponential_factor)
    opts = Keyword.put_new(opts, :fallback_function, nil)
    opts
  end

  defp exponential_retry!(func, opts) do
    {:ok, result} = do_retry(func, opts[:retries], opts[:base_delay], opts)
    result
  end

  defp do_retry(func, 0, _delay, opts) do
    case opts[:fallback_function] do
      nil -> {:ok, func.()}
      fallback when is_function(fallback) -> {:ok, fallback.()}
    end
  end

  defp do_retry(func, retries, delay, opts) do
    exponential_factor = opts[:exponential_factor]

    try do
      {:ok, func.()}
    catch
      :exit, _ ->
        Logger.error("Retry attempt failed, #{retries} attempts remaining.")

        Process.sleep(delay)
        do_retry(func, retries - 1, delay * exponential_factor + :rand.uniform(delay), opts)
    end
  end
end
