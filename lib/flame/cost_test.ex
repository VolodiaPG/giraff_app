defmodule FLAME.CostTestBackend do
  @behaviour FLAME.Backend

  alias FLAME.CostTestBackend

  require Logger

  defstruct local_backend: nil,
            on_accepted_offer: nil,
            on_new_boot: nil,
            name: nil,
            price: 0

  @impl true
  def init(opts) do
    Logger.debug("CostTest backend init with opts: #{inspect(opts)}")

    {:ok, res} = FLAME.LocalBackend.init(opts)

    on_accepted_offer = Keyword.get(opts, :on_accepted_offer)
    name = Keyword.get(opts, :name)
    price = Keyword.get(opts, :price)
    on_new_boot = Keyword.get(opts, :on_new_boot)

    {:ok,
     %CostTestBackend{
       local_backend: res,
       on_accepted_offer: on_accepted_offer,
       on_new_boot: on_new_boot,
       name: name,
       price: price
     }}
  end

  @impl true
  def remote_spawn_monitor(%CostTestBackend{local_backend: local_backend}, term) do
    FLAME.LocalBackend.remote_spawn_monitor(local_backend, term)
  end

  @impl true
  def system_shutdown do
    FLAME.LocalBackend.system_shutdown()
  end

  @impl true
  def remote_boot(
        %costtestbackend{
          local_backend: local_backend,
          price: price,
          name: name
        } = state
      ) do
    if state.on_new_boot, do: state.on_new_boot.(%{name: name})
    {:ok, terminator_pid, local_backend} = FLAME.LocalBackend.remote_boot(local_backend)
    if state.on_accepted_offer, do: state.on_accepted_offer.(%{name: name, price: price})
    {:ok, terminator_pid, %{state | local_backend: local_backend}}
  end
end
