# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tokenizers, Tokenizers.Native, skip_compilation?: true

config :giraff,
  generators: [timestamp_type: :utc_datetime]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id, :span_id]

config :opentelemetry,
  traces_exporter: :otlp

config :nx, default_backend: EXLA.Backend

import_config "#{config_env()}.exs"
