defmodule Giraff.Cost do
  @moduledoc """
  Cost module responsible to tracking the cost and checking what is the best
  strategy to use for scaling regarding the cost.
  """

  use GenServer
  require Logger

  alias Giraff.Cost.GrowError
  alias Giraff.Cost

  defstruct budget: 0, db: %{}

  def start_link(args) do
    name = Keyword.get(args, :name, Cost)

    GenServer.start_link(Cost, args, name: name)
  end

  @impl true
  def init(args) do
    state = Map.merge(%Cost{}, Map.new(args))

    {:ok, state}
  end

  @impl true
  def handle_call(:new_request, _from, state) do
    new_budget = state.budget + Application.get_env(:giraff, :new_budget_per_request)
    new_state = %{state | budget: new_budget}

    {:noreply, new_state}
  end

  def handle_call({:scale_out, scale_out_type, function_name}, _from, state) do
    Logger.debug("got db #{inspect(state.db)}, and budget #{state.budget},
      function_name #{function_name}, scale_out_type #{scale_out_type},
      #{state.db[function_name]}.")

    case state.db[function_name] do
      nil ->
        Logger.warning("Choosing to default to scaling")
        {:reply, :scaling, state}

      cost ->
        cond do
          cost <= state.budget ->
            new_budget = state.budget - cost
            Logger.debug("Choosing to scale out")
            {:reply, :scaling, %{state | budget: new_budget}}

          cost > state.budget and scale_out_type === :degraded ->
            Logger.debug("Choosing to wait")
            {:reply, :wait, state}

          cost > state.budget and scale_out_type === :nominal ->
            Logger.debug("Choosing to degrade")
            {:reply, :degraded, state}
        end
    end
  end

  def handle_call({:perform, :scaling, function_name, cost}, _from, state) do
    new_budget = state.budget - cost

    new_db = Map.put(state.db, function_name, cost)

    new_state = %{state | budget: new_budget, db: new_db}
    Logger.debug("put #{function_name} with #{cost} in #{inspect(state.db)}")

    {:reply, :scaling, new_state}
  end

  def handle_call({:perform, :degraded, cost}, _from, state) do
    new_budget = state.budget - cost
    new_state = %{state | budget: new_budget}

    {:reply, :scaling, new_state}
  end

  def on_new_boot(cost_pid, %{name: name}) do
    case GenServer.call(cost_pid, {:scale_out, :nominal, to_string(name)}) do
      :scaling ->
        :ok

      :degraded ->
        raise GrowError,
          code: :degraded,
          message: "cannot scale out #{name} because it is degraded"

      :wait ->
        raise GrowError, code: :wait, message: "cannot scale out #{name} because it
        is waiting"
    end
  end

  def on_accepted_offer(cost_pid, %{name: name, price: price}) do
    GenServer.call(cost_pid, {:perform, :scaling, to_string(name), price})
  end
end

defmodule Giraff.Cost.GrowError do
  defexception [:message, :code]
end
