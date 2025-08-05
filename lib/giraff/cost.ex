defmodule Giraff.Cost.Error do
  defstruct [:message, :code]
end

defmodule Giraff.Cost do
  @moduledoc """
  Cost module responsible to tracking the cost and checking what is the best
  strategy to use for scaling regarding the cost.
  """

  use GenServer
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Giraff.Cost

  defstruct budget: 0, nb_requests_to_wait: nil, nb_requests_in_flight: 0, db: %{}

  def start_link(args) do
    name = Keyword.get(args, :name, nil)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    state = Map.merge(%Cost{}, Map.new(args))

    {:ok, state}
  end

  @impl true
  def handle_call(:new_request_start, _from, state) do
    Logger.debug(
      "Got new request start #{inspect(Application.fetch_env!(:giraff,
      :new_budget_per_request))}"
    )

    new_budget = state.budget + Application.fetch_env!(:giraff, :new_budget_per_request)

    new_state = %{
      state
      | budget: new_budget,
        nb_requests_in_flight: state.nb_requests_in_flight + 1
    }

    {:reply, :ok, new_state}
  end

  def handle_call(:new_request_end, _from, state) do
    Logger.debug("Got new request end")

    new_state = %{
      state
      | nb_requests_in_flight: state.nb_requests_in_flight - 1
    }

    {:reply, :ok, new_state}
  end

  # Todo: nb requests in flight should be per function and not global
  # should also be the case for nb request to wait

  def handle_call({:scale_out, function_name}, _from, state) do
    Logger.debug("Got function #{function_name} with budget #{state.budget}")

    case state.db[function_name] do
      nil ->
        Logger.warning("Choosing to default to scaling")
        new_state = %{state | db: Map.put(state.db, function_name, :deploying)}
        {:reply, :scaling, new_state}

      :deploying ->
        Logger.warning("Choosing to default to waiting")
        {:reply, {:wait, :no_decrement}, state}

      cost ->
        cond do
          not is_nil(state.nb_requests_to_wait) and
              state.nb_requests_in_flight > state.nb_requests_to_wait ->
            Logger.debug("Choosing to wait")
            {:reply, :wait, state}

          cost <= state.budget ->
            new_budget = state.budget - cost
            Logger.debug("Choosing to scale out")
            {:reply, :scaling, %{state | budget: new_budget}}

          cost > state.budget ->
            Logger.debug("Choosing to degrade")
            {:reply, :degraded, state}
        end
    end
  end

  def handle_call({:booted, function_name, cost}, _from, state) do
    Tracer.with_span "new_function_booted" do
      new_budget = state.budget - cost
      new_db = Map.put(state.db, function_name, cost)

      Tracer.set_attribute("budget", state.budget)
      Tracer.set_attribute("cost", cost)
      Tracer.set_attribute("new_budget", new_budget)
      Tracer.set_attribute("function_name", function_name)

      new_state = %{state | budget: new_budget, db: new_db}
      Logger.debug("put #{function_name} with #{cost} in #{inspect(state.db)}")

      {:reply, :scaling, new_state}
    end
  end

  def on_new_boot(cost_pid, %{name: name}) do
    case GenServer.call(cost_pid, {:scale_out, to_string(name)}) do
      :scaling ->
        :ok

      other ->
        Process.exit(self(), {:error, {:cost, other}})
    end
  end

  def on_accepted_offer(cost_pid, %{name: name, price: price}) do
    GenServer.call(cost_pid, {:booted, to_string(name), price})
  end

  def on_new_request_start(cost_pid) do
    GenServer.call(cost_pid, :new_request_start)
  end

  def on_new_request_end(cost_pid) do
    GenServer.call(cost_pid, :new_request_end)
  end
end
