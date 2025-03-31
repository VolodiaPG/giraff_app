defmodule AI.Vosk do
  use GenServer

  require Logger

  @timeout 120_000

  def start_link() do
    GenServer.start_link(__MODULE__, nil)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  def call(my_string) do
    Task.async(fn ->
      :poolboy.transaction(
        :python_worker,
        fn pid ->
          GenServer.call(pid, {:handle, my_string}, :infinity)
        end,
        @timeout
      )
    end)
    |> Task.await(@timeout)
  end

  #############
  # Callbacks #
  #############

  @impl true
  def init(_) do
    path =
      [:code.priv_dir(:giraff), "python"]
      |> Path.join()

    with {:ok, pid} <- :python.start([{:python_path, to_charlist(path)}, {:python, ~c"python3"}]) do
      Logger.info("[#{__MODULE__}] Started python worker")
      {:ok, pid}
    end
  end

  @impl true
  def handle_call({:handle, audio_data}, _from, pid) do
    result = :python.call(pid, :speech_vosk, :handle, [audio_data])
    Logger.info("[#{__MODULE__}] Handled call")
    {:reply, {:ok, result}, pid}
  end
end
