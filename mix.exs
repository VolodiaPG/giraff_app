defmodule Thumbs.MixProject do
  use Mix.Project

  def project do
    [
      app: :giraff,
      version: "0.1.1",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
      # releases: [
      #     giraff: [
      #         vm_args: "rel/vm.args"
      #     ]
      # ]
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
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.6"},
      {:flame, ">= 0.2.0"},
      {:req, "~> 0.5.6"},
      {:ex_cmd, "~> 0.10.0"},
      {:plug, "~> 1.15"},
      # For ai model loading
      {:bumblebee, "~> 0.6.0"},
      # for using JIT for models on the cpu/gpu
      {:exla, ">= 0.0.0"}
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
    ]
  end
end
