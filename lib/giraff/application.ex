defmodule Giraff.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      children(
        always: {Task.Supervisor, name: Giraff.TaskSup},
        always: {DynamicSupervisor, name: Giraff.DynamicSup},
        parent: {
          FLAME.Pool,
          name: Giraff.SpeechToTextBackend,
          min: 0,
          max: 100,
          max_concurrency: 5,
          boot_timeout: :timer.minutes(1),
          shutdown_timeout: :timer.minutes(1),
          idle_shutdown_after: :timer.minutes(4),
          timeout: :timer.minutes(1),
          log: :debug,
          single_use: false,
          backend: Application.get_env(:giraff, :speech_to_text_backend)
        },
        flame: fn
          val when val in [nil, %FLAME.Parent{backend_app: Giraff.SpeechToTextBackend}] ->
            {
              FLAME.Pool,
              name: Giraff.TextToSpeechBackend,
              min: 0,
              max: 10,
              max_concurrency: 5,
              boot_timeout: :timer.minutes(2),
              shutdown_timeout: :timer.minutes(2),
              idle_shutdown_after: :timer.minutes(2),
              timeout: :timer.minutes(2),
              log: :debug,
              single_use: false,
              backend: Application.get_env(:giraff, :text_to_speech_backend)
            }

          parent ->
            Logger.warning("Unexpected parent: #{inspect(parent)}")
            nil
        end,
        flame: fn
          val when val in [nil, %FLAME.Parent{backend_app: Giraff.TextToSpeechBackend}] ->
            {
              FLAME.Pool,
              name: Giraff.EndGameBackend,
              min: 0,
              max: 10,
              max_concurrency: 5,
              boot_timeout: :timer.minutes(2),
              shutdown_timeout: :timer.minutes(2),
              idle_shutdown_after: :timer.minutes(2),
              timeout: :timer.minutes(2),
              log: :debug,
              single_use: false,
              backend: Application.get_env(:giraff, :end_game_backend)
            }

          parent ->
            Logger.warning("Unexpected parent: #{inspect(parent)}")
            nil
        end,
        always: {Bandit, plug: GiraffWeb.Endpoint, port: Application.get_env(:giraff, :port)},
        flame: {AI.SpeechRecognitionServer, []}
      )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Giraff.Supervisor]
    config = Application.fetch_env!(:giraff, Giraff.Application)
    Logger.info("Starting #{config[:env]} application...")

    Supervisor.start_link(children, opts)
  end

  defp children(child_specs) do
    parent = FLAME.Parent.get()
    is_parent? = is_nil(parent)
    is_flame? = !is_parent? || FLAME.Backend.impl() == FLAME.LocalBackend

    Logger.info("is_parent? #{is_parent?}")
    Logger.info("is_flame? #{is_flame?} (backend: #{FLAME.Backend.impl()})")

    child_specs
    |> Enum.flat_map(fn
      {:always, spec} when is_function(spec, 1) ->
        [spec.(parent)]

      {:always, spec} ->
        [spec]

      {:parent, spec} when is_function(spec, 1) and is_parent? ->
        [spec.(parent)]

      {:parent, spec} when is_parent? ->
        [spec]

      {:parent, _spec} ->
        []

      {:flame, spec} when is_function(spec, 1) and is_flame? ->
        [spec.(parent)]

      {:flame, spec} when is_flame? ->
        [spec]

      {:flame, _spec} ->
        []
    end)
    |> Enum.reject(&is_nil/1)
  end
end
