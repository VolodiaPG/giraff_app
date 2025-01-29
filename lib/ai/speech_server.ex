defmodule AI.SpeechRecognitionServer do
  use GenServer
  require Logger
  alias AI.SpeechRecognition

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def get_serving do
    GenServer.call(__MODULE__, :get_serving, :infinity)
  end

  @impl true
  def init(_) do
    case SpeechRecognition.setup_whisper() do
      {:ok, serving} ->
        Logger.info("Whisper model loaded successfully")
        {:ok, serving}

      error ->
        Logger.error("Failed to initialize Whisper: #{inspect(error)}")
        {:stop, :whisper_init_failed}
    end
  end

  @impl true
  def handle_call(:get_serving, _from, serving) do
    {:reply, serving, serving}
  end
end
