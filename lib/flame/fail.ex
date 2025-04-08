defmodule FLAME.FailBackend do
  @behaviour FLAME.Backend

  alias FLAME.FailBackend

  require Logger

  defstruct local_backend: nil,
            fail_after_counter: nil

  @impl true
  def init(opts) do
    Logger.debug("Fail backend init with opts: #{inspect(opts)}")

    {:ok, res} = FLAME.LocalBackend.init(opts)

    fail_after_counter = Keyword.get(opts, :fail_after_counter)

    if not is_pid(fail_after_counter) do
      raise "fail_after_counter must be a pid"
    end

    {:ok,
     %FailBackend{
       local_backend: res,
       fail_after_counter: fail_after_counter
     }}
  end

  @impl true
  def remote_spawn_monitor(%FailBackend{local_backend: local_backend}, term) do
    FLAME.LocalBackend.remote_spawn_monitor(local_backend, term)
  end

  @impl true
  def system_shutdown do
    FLAME.LocalBackend.system_shutdown()
  end

  @impl true
  def remote_boot(
        %FailBackend{local_backend: local_backend, fail_after_counter: fail_after} = state
      )
      when is_pid(fail_after) do
    if GenServer.call(fail_after, :get) == 0 do
      raise "Debug: emulating backend failure"
    else
      case FLAME.LocalBackend.remote_boot(local_backend) do
        {:ok, terminator_pid, local_backend} when is_pid(terminator_pid) ->
          GenServer.call(fail_after, :dec)
          new_state = %{state | local_backend: local_backend}

          {:ok, terminator_pid, new_state}
      end
    end
  end
end

defmodule FLAME.FailBackend.Counter do
  use GenServer

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  def init(opts) do
    {:ok, Keyword.get(opts, :initial_value, 0)}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:dec, _from, state) do
    {:reply, :ok, max(0, state - 1)}
  end

  def handle_call({:set, value}, _from, _state) do
    {:reply, :ok, value}
  end
end
