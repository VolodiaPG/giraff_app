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
        parent: {DNSCluster, query: Application.get_env(:thumbs, :dns_cluster_query) || :ignore},
        always: {Task.Supervisor, name: Giraff.TaskSup},
        always: {DynamicSupervisor, name: Giraff.DynamicSup},
        parent: {
          FLAME.Pool,
          name: Giraff.FFMpegRunner,
          min: 0,
          max: 10,
          max_concurrency: 5,
          boot_timeout: :timer.minutes(2),
          shutdown_timeout: :timer.minutes(2),
          idle_shutdown_after: :timer.minutes(2),
          timeout: :timer.minutes(2),
          log: :debug,
          single_use: false
          # code_sync: [
          #   start_apps: true,
          #   verbose: true,
          #   sync_beams: [
          #     Path.join([
          #       "_build",
          #       "prod",
          #       "lib",
          #       "thumbs",
          #       "ebin"
          #     ])
          #   ]
          # ]
        },
        parent: {Bandit, plug: GiraffWeb.Endpoint, port: 8080}
      )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Giraff.Supervisor]
    config = Application.fetch_env!(:giraff, Giraff.Application)
    Logger.info("Starting #{config[:env]} application...")

    Supervisor.start_link(children, opts)
  end

  defp children(child_specs) do
    is_parent? = is_nil(FLAME.Parent.get())
    is_flame? = !is_parent? || FLAME.Backend.impl() == FLAME.LocalBackend

    Enum.flat_map(child_specs, fn
      {:always, spec} -> [spec]
      {:parent, spec} when is_parent? == true -> [spec]
      {:parent, _spec} when is_parent? == false -> []
      {:flame, spec} when is_flame? == true -> [spec]
      {:flame, _spec} when is_flame? == false -> []
    end)
  end
end
