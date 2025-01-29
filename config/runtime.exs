import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

config :giraff,
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") || :crypto.strong_rand_bytes(64) |> Base.encode64()

config :giraff, Giraff.Application, env: config_env()

config :giraff, port: System.get_env("PORT") || 5000

IO.puts("Running in environment: #{System.get_env("MIX_ENV")} with config_env() #{config_env()}")

docker_registry = System.get_env("DOCKER_REGISTRY") || "ghcr.io/volodiapg"

# Define common pool configurations for each backend type
backend_configs = %{
  end_game_backend: %{
    name: :flame_end_game,
    module: Giraff.EndGameBackend,
    image: "#{docker_registry}/giraff:giraff_app",
    millicpu: 200,
    memory_mb: 256,
    min: 0,
    max_concurrency: 100,
    latency_max_ms: 10000
  },
  speech_to_text_backend: %{
    name: :flame_speech_to_text,
    module: Giraff.SpeechToTextBackend,
    image: "#{docker_registry}/giraff:giraff_speech",
    millicpu: 1000,
    memory_mb: 2048,
    min: 1,
    max_concurrency: 10,
    latency_max_ms: 10000
  },
  sentiment_backend: %{
    name: :flame_sentiment,
    module: Giraff.SentimentBackend,
    image: "#{docker_registry}/giraff:giraff_sentiment",
    millicpu: 1000,
    memory_mb: 2048,
    min: 1,
    max_concurrency: 10,
    latency_max_ms: 10000
  },
  text_to_speech_backend: %{
    name: :flame_text_to_speech,
    module: Giraff.TextToSpeechBackend,
    image: "#{docker_registry}/giraff:giraff_tts",
    millicpu: 256,
    memory_mb: 512,
    min: 0,
    max_concurrency: 25,
    latency_max_ms: 10000
  }
}

# Common pool settings
common_pool_settings = [
  max: 100,
  boot_timeout: :timer.minutes(2),
  shutdown_timeout: :timer.minutes(2),
  idle_shutdown_after: :timer.minutes(2),
  timeout: :timer.minutes(2),
  log: :debug,
  single_use: false
]

IO.puts("config_env() #{config_env()}")

case config_env() do
  :prod ->
    config :flame, :terminator, log: :debug
    config :flame, :backend, FLAME.GiraffBackend

    for {backend_type, config} <- backend_configs do
      config_key = :"#{backend_type}"

      backend_config = {
        FLAME.GiraffBackend,
        name: config.name,
        market: System.get_env("MARKET_URL"),
        boot_timeout: 120_000,
        image: config.image,
        millicpu: config.millicpu,
        memory_mb: config.memory_mb,
        duration: 120_000,
        latency_max_ms: config.latency_max_ms,
        target_entrypoint: System.get_env("GIRAFF_NODE_ID"),
        from: System.get_env("GIRAFF_NODE_ID")
      }

      pool_config =
        Keyword.merge(common_pool_settings,
          name: config.module,
          min: config.min,
          max_concurrency: config.max_concurrency,
          backend: backend_config
        )

      config :giraff, config_key, {FLAME.Pool, pool_config}
    end

  :docker ->
    config :flame, :terminator, log: :debug
    config :flame, :backend, FLAME.DockerBackend

    for {backend_type, config} <- backend_configs do
      config_key = :"#{backend_type}"

      backend_config = {
        FLAME.DockerBackend,
        name: config.name,
        host: "http+unix://%2Fvar%2Frun%2Fdocker.sock",
        boot_timeout: 120_000,
        image: config.image,
        millicpu: config.millicpu,
        memory_mb: config.memory_mb
      }

      pool_config =
        Keyword.merge(common_pool_settings,
          name: config.module,
          min: config.min,
          max_concurrency: config.max_concurrency,
          backend: backend_config
        )

      config :giraff, config_key, {FLAME.Pool, pool_config}
    end

  _ ->
    config :flame, :backend, FLAME.LocalBackend

    for {backend_type, config} <- backend_configs do
      config_key = :"#{backend_type}"

      pool_config =
        Keyword.merge(common_pool_settings,
          name: config.module,
          min: config.min,
          max_concurrency: config.max_concurrency,
          backend: FLAME.LocalBackend
        )

      config :giraff, config_key, {FLAME.Pool, pool_config}
    end
end
