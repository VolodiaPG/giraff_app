import Config

config :logger, :console, format: "[$level] $message\n"

config :flame, :backend, FLAME.DockerBackend
