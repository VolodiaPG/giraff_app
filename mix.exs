defmodule Giraff.MixProject do
  use Mix.Project

  def project do
    [
      app: :giraff,
      version: "0.1.1",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() != :dev,
      aliases: aliases(),
      deps: deps(),
      releases: [
        giraff: [
          applications: [opentelemetry_exporter: :permanent, opentelemetry: :temporary]
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Giraff.Application, []},
      extra_applications: [:logger]
      # registered: [:custom_epmd, :custom_dst]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.6"},
      {:flame,
       git: "https://github.com/volodiapg/flame.git",
       branch: "make-pool-allow-for-backend-init-error-pass-caller"},
      # {:flame, path: "../flame"},
      # {:flame, "~> 0.5.2"},
      {:req, "~> 0.5.6"},
      {:ex_cmd, "~> 0.10.0"},
      {:plug, "~> 1.15"},
      # For ai model loading
      {:bumblebee, "~> 0.6.0"},
      # for using JIT for models on the cpu/gpu
      {:exla, ">= 0.9.2"},
      {:deps_nix, "~> 2.0", only: :dev},
      {:rustler, ">= 0.0.0", optional: true},
      {:httpoison, "~> 2.0"},
      {:erlport, "~>0.11.0"},
      {:poolboy, "~> 1.5"},
      # OpenTelemetry dependencies
      {:opentelemetry, "~> 1.5.0"},
      {:opentelemetry_api, "~> 1.4.0"},
      {:opentelemetry_exporter, "~> 1.8.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      # "rebar.setup": ["local.rebar --force"],
      # hex_setup: [
      #   "hex.setup",
      #        "rebar.setup"
      #      ],
      "deps.get": ["deps.get", "deps.nix"],
      "deps.update": ["deps.update", "deps.nix"]
    ]
  end
end
