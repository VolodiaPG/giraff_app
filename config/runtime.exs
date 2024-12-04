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
if System.get_env("PHX_SERVER") do
  config :giraff, ThumbsWeb.Endpoint, server: true
end

config :giraff, Giraff.Application, env: config_env()

if config_env() == :prod do
  config :flame, :backend, FLAME.MicroVMBackend

  config :flame, FLAME.MicroVMBackend,
    boot_timeout: 120_000,
    host: "dell"

  config :flame, :terminator, log: :debug

  config :giraff, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
