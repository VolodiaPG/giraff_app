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

    children =
      children(
        parent: speech_to_text_backend,
        parent: text_to_speech_backend,
        flame_text_to_speech: end_game_backend,
        flame_speech_to_text: sentiment_backend,
        flame_speech_to_text: end_game_backend,
        flame_speech_to_text: AI.SpeechRecognitionServer,
        flame_sentiment: AI.SentimentServer
      )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Giraff.Supervisor]
    config = Application.fetch_env!(:giraff, Giraff.Application)
    Logger.info("Starting #{config[:env]} application...")

    {:ok, sup} =
      Supervisor.start_link(
        [
          {Task.Supervisor, name: Giraff.TaskSup},
          {DynamicSupervisor, name: Giraff.DynamicSup},
          {Bandit, plug: GiraffWeb.Endpoint, port: Application.get_env(:giraff, :port)}
        ],
        opts
      )

    children
    |> Enum.map(fn child_spec ->
      Task.async(fn ->
        Supervisor.start_child(sup, child_spec)
      end)
    end)
    |> Task.await_many(:timer.minutes(1))

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
end
