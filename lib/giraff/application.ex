defmodule Giraff.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    end_game_backend = Application.fetch_env!(:giraff, :end_game_backend)
    speech_to_text_backend = Application.fetch_env!(:giraff, :speech_to_text_backend)
    sentiment_backend = Application.fetch_env!(:giraff, :sentiment_backend)
    text_to_speech_backend = Application.fetch_env!(:giraff, :text_to_speech_backend)
    vosk_speech_to_text_backend = Application.fetch_env!(:giraff, :vosk_speech_to_text_backend)

    children =
      children(
        always: {Task.Supervisor, name: Giraff.TaskSup},
        always: {DynamicSupervisor, name: Giraff.DynamicSup},
        flame_vosk_speech_to_text: :poolboy.child_spec(:worker, vosk_poolboy_config()),
        flame_speech_to_text: AI.SpeechRecognitionServer,
        flame_sentiment: AI.SentimentServer,
        parent: speech_to_text_backend,
        parent: text_to_speech_backend,
        parent: vosk_speech_to_text_backend,
        flame_text_to_speech: end_game_backend,
        flame_speech_to_text: sentiment_backend,
        flame_speech_to_text: end_game_backend,
        flame_vosk_speech_to_text: sentiment_backend,
        flame_vosk_speech_to_text: end_game_backend,
        always: {Bandit, plug: GiraffWeb.Endpoint, port: Application.get_env(:giraff, :port)}
      )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Giraff.Supervisor]
    config = Application.fetch_env!(:giraff, Giraff.Application)
    Logger.info("Starting #{config[:env]} application...")
    {:ok, sup} = Supervisor.start_link(children, opts)

    # {:ok, sup} =
    #   Supervisor.start_link(
    #     [
    #       {Task.Supervisor, name: Giraff.TaskSup},
    #       {DynamicSupervisor, name: Giraff.DynamicSup}
    #     ],
    #     opts
    #   )

    # # Start async children
    # Enum.each(children, fn child_spec ->
    #   Task.Supervisor.start_child(Giraff.TaskSup, fn ->
    #     DynamicSupervisor.start_child(Giraff.DynamicSup, child_spec)
    #   end)
    # end)

    # Wait for all children to start
    # Task.start(fn ->
    #   start_time = System.monotonic_time(:millisecond)
    #   wait_interval = 100
    #   timeout = :timer.minutes(1)

    #   Stream.interval(wait_interval)
    #   |> Stream.take_while(fn _ ->
    #     elapsed = System.monotonic_time(:millisecond) - start_time

    #     if elapsed > timeout do
    #       Logger.warning("Timeout waiting for children to start")
    #       false
    #     else
    #       case DynamicSupervisor.count_children(Giraff.DynamicSup) do
    #         %{active: active, specs: specs} when active == specs and specs == length(children) ->
    #           Logger.info("All #{specs} children started successfully, starting web server")

    #           Supervisor.start_child(
    #             sup,
    #             {Bandit, plug: GiraffWeb.Endpoint, port: Application.get_env(:giraff, :port)}
    #           )

    #           false

    #         _ ->
    #           true
    #       end
    #     end
    #   end)
    #   |> Stream.run()
    # end)

    {:ok, sup}
  end

  defp children(child_specs) do
    parent = FLAME.Parent.get()
    is_parent? = is_nil(parent)
    is_local? = FLAME.Backend.impl() == FLAME.LocalBackend
    is_flame? = !is_parent? || is_local?

    Logger.info("is_parent? #{is_parent?}")
    Logger.info("is_flame? #{is_flame?} (backend: #{FLAME.Backend.impl()})")
    Logger.info("is_local? #{is_local?}")

    child_specs
    |> Enum.flat_map(fn
      {:always, spec} ->
        [spec]

      {:parent, spec} when is_parent? ->
        [spec]

      {:parent, _spec} ->
        []

      {:flame, spec} when is_flame? ->
        [spec]

      {:flame, _spec} ->
        []

      {_arg, spec} when is_local? ->
        [spec]

      {arg, spec} when is_flame? ->
        if String.starts_with?(parent.node_base, [to_string(arg)]) do
          Logger.info(
            "Starting #{inspect(spec)} because #{arg} matches the parent node base #{parent.node_base}"
          )

          [spec]
        else
          []
        end

      {_arg, _spec} ->
        []
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp vosk_poolboy_config do
    [
      {:name, {:local, :python_worker}},
      {:worker_module, AI.Vosk},
      # Pool size
      {:size, 5},
      # How many workers can be started above the size
      {:max_overflow, 5}
    ]
  end
end
