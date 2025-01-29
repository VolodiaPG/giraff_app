defmodule AI.SentimentServer do
  use GenServer
  require Logger
  alias AI.SentimentRecognition

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def get_serving do
    GenServer.call(__MODULE__, :get_serving, :infinity)
  end

  @impl true
  @spec init(any()) :: {:ok, Nx.Serving.t()} | {:stop, :bert_tweeter_init_failed}
  def init(_) do
    case SentimentRecognition.setup() do
      {:ok, serving} ->
        Logger.info("BERT Tweeter model loaded successfully")
        {:ok, serving}

      error ->
        Logger.error("Failed to initialize BERT Tweeter: #{inspect(error)}")
        {:stop, :bert_tweeter_init_failed}
    end
  end

  @impl true
  def handle_call(:get_serving, _from, serving) do
    {:reply, serving, serving}
  end
end
