defmodule Giraff.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @sup_opts [strategy: :one_for_one, name: Giraff.Supervisor]

  @impl true
  def start(_type, _args) do
    config = Application.fetch_env!(:giraff, Giraff.Application)

    on_new_boot = fn arg ->
      Giraff.Cost.on_new_boot({:global, :cost_server}, arg)
    end

    on_accepted_offer = fn arg ->
      Giraff.Cost.on_accepted_offer({:global, :cost_server}, arg)
    end

    backends =
      [
        Application.fetch_env!(:giraff, :end_game_backend),
        Application.fetch_env!(:giraff, :speech_to_text_backend),
        Application.fetch_env!(:giraff, :sentiment_backend),
        Application.fetch_env!(:giraff, :text_to_speech_backend),
        Application.fetch_env!(:giraff, :vosk_speech_to_text_backend)
      ]
      |> Enum.map(fn arg ->
        if config[:env] != :test do
          {pool, pool_config} = arg
          {backend, backend_config} = Keyword.fetch!(pool_config, :backend)

          new_backend_config =
            Keyword.merge(backend_config,
              on_new_boot: on_new_boot,
              on_accepted_offer: on_accepted_offer
            )

          new_config =
            Keyword.merge(pool_config,
              backend: {backend, new_backend_config}
            )

          {pool, new_config}
        else
          arg
        end
      end)
      |> Enum.map(fn pool ->
        {:always, pool}
      end)

    children_args =
      [
        always: {Task.Supervisor, name: Giraff.TaskSup},
        always: {DynamicSupervisor, name: Giraff.DynamicSup},
        flame_vosk_speech_to_text: :poolboy.child_spec(:worker, vosk_poolboy_config()),
        flame_speech_to_text: AI.SpeechRecognitionServer,
        flame_sentiment: AI.SentimentServer,
        parent: {Giraff.Cost, [name: {:global, :cost_server}, nb_requests_to_wait: 4]}
        #         parent: text_to_speech_backend,
        #         parent: vosk_speech_to_text_backend,
        #         parent: sentiment_backend,
        # flame_text_to_speech: end_game_backend,
        # flame_speech_to_text: sentiment_backend,
        # flame_speech_to_text: end_game_backend,
        # flame_vosk_speech_to_text: sentiment_backend,
        # flame_vosk_speech_to_text: end_game_backend,
        # flame_sentiment: end_game_backend,
      ] ++
        backends ++
        [
          always: {Bandit, plug: GiraffWeb.Endpoint, port: Application.get_env(:giraff, :port)}
        ]

    children = children(children_args)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    Logger.info("Starting #{config[:env]} application...")
    {:ok, sup} = Supervisor.start_link(children, @sup_opts)

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
      {:size, 3},
      # How many workers can be started above the size
      {:max_overflow, 2}
    ]
  end
end
