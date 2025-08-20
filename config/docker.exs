import Config

config :logger, :console, format: "[$level] $message\n"

config :flame, :backend, FLAME.DockerBackend

config :giraff, :docker_host, "http+unix://%2Fvar%2Frun%2Fdocker.sock"

config :giraff, :cost_per_request, 0.1

config :giraff, :always_fallback, true
