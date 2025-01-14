import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/thumbs start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.

config :giraff, secret_key_base: System.get_env("SECRET_KEY_BASE")

config :giraff, Giraff.Application, env: config_env()

if config_env() == :prod do
  config :giraff,
    ffmpeg_backend: {
      FLAME.GiraffBackend,
      market: System.get_env("MARKET_URL"),
      boot_timeout: 120_000,
      image: "ghcr.io/volodiapg/giraff:giraff_app",
      millicpu: 100,
      memory_mb: 256,
      duration: 120_000,
      latency_max_ms: 1000,
      target_entrypoint: System.get_env("GIRAFF_NODE_ID"),
      from: System.get_env("GIRAFF_NODE_ID")
    }

  config :giraff,
    toto_backend: {
      FLAME.GiraffBackend,
      market: System.get_env("MARKET_URL"),
      boot_timeout: 120_000,
      image: "ghcr.io/volodiapg/giraff:giraff_app",
      millicpu: 500,
      memory_mb: 512,
      duration: 120_000,
      latency_max_ms: 200,
      target_entrypoint: System.get_env("GIRAFF_NODE_ID"),
      from: System.get_env("GIRAFF_NODE_ID")
    }

  config :flame, :terminator, log: :debug

  config :giraff, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
else
  config :giraff, ffmpeg_backend: FLAME.LocalBackend

  config :giraff, toto_backend: FLAME.LocalBackend
end
