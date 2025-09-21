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

config :giraff, docker_registry: docker_registry

otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT_FUNCTION")

IO.puts("Using otel at #{otel_endpoint}")

config :giraff, otel_endpoint: otel_endpoint

name = System.get_env("ID") || System.get_env("NAME") || "giraff_application"
namespace = System.get_env("OTEL_NAMESPACE") || name
config :flame, otel_namespace: namespace

config :opentelemetry, :resource,
  service: %{
    name: name,
    namespace: namespace,
    version: "0.0.1"
  }

config :opentelemetry, :processors,
  otel_batch_processor: %{
    exporter: {:opentelemetry_exporter, %{endpoints: [otel_endpoint]}}
  }

config :opentelemetry_exporter,
  otlp_protocol: :grpc,
  otlp_endpoint: otel_endpoint

# Define common pool configurations for each backend type
backend_configs = %{
  end_game_backend: %{
    name: :flame_end_game,
    module: Giraff.EndGameBackend,
    image: "#{docker_registry}/giraff:giraff_app",
    millicpu: 200,
    memory_mb: 256,
    min: 0,
    max_concurrency: 20,
    latency_max_ms: 1_000
  },
  speech_to_text_backend: %{
    name: :flame_speech_to_text,
    module: Giraff.SpeechToTextBackend,
    image: "#{docker_registry}/giraff:giraff_speech",
    millicpu: 2000,
    memory_mb: 2000,
    min: 0,
    max_concurrency: 4,
    # 15 ms latency in the link, one way
    latency_max_ms: 150
  },
  vosk_speech_to_text_backend: %{
    name: :flame_vosk_speech_to_text,
    module: Giraff.VoskSpeechToTextBackend,
    image: "#{docker_registry}/giraff:giraff_vosk_speech",
    millicpu: 1000,
    memory_mb: 1500,
    min: 0,
    max_concurrency: 4,
    # > 20 ms latency in the link, one way
    latency_max_ms: 300
  },
  sentiment_backend: %{
    name: :flame_sentiment,
    module: Giraff.SentimentBackend,
    image: "#{docker_registry}/giraff:giraff_sentiment",
    millicpu: 1000,
    memory_mb: 2048,
    min: 0,
    max_concurrency: 4,
    latency_max_ms: 150
  },
  text_to_speech_backend: %{
    name: :flame_text_to_speech,
    module: Giraff.TextToSpeechBackend,
    image: "#{docker_registry}/giraff:giraff_tts",
    millicpu: 500,
    memory_mb: 512,
    min: 0,
    max_concurrency: 4,
    latency_max_ms: 300
  }
}

new_budget_per_request = System.get_env("NEW_BUDGET_PER_REQUEST", "10")

config :giraff,
       :new_budget_per_request,
       String.to_integer(new_budget_per_request)

initial_budget = System.get_env("INITIAL_BUDGET", "0")

config :giraff,
       :initial_budget,
       String.to_integer(initial_budget)

no_fallbacks = System.get_env("NO_FALLBACKS", "false")
config :giraff, no_fallbacks: no_fallbacks == "true"

common_backend_settings = %{
  env: %{
    "NEW_BUDGET_PER_REQUEST" => new_budget_per_request,
    "INITIAL_BUDGET" => initial_budget,
    "NO_FALLBACKS" => no_fallbacks
  }
}

# Common pool settings
common_pool_settings = [
  max: 10000,
  boot_timeout: :timer.minutes(2),
  shutdown_timeout: :timer.minutes(2),
  idle_shutdown_after: :infinity,
  timeout: :timer.minutes(2),
  # log: :debug
  log: :debug,
  single_use: false
]

IO.puts("config_env() #{config_env()}")

paid_at =
  case System.get_env("PAID_AT") do
    nil ->
      nil

    paid_at_str ->
      case DateTime.from_iso8601(paid_at_str) do
        {:ok, datetime, _} -> datetime
        {:error, _} -> nil
      end
  end

sla =
  case System.get_env("SLA") do
    nil ->
      nil

    sla_str ->
      Jason.decode!(sla_str)
  end

# paid_at = DateTime.utc_now()

# sla =
#   ~s({"id":"6cd8c0e4-67b2-4a05-9a9b-2e367c44b131","memory":"256.0 MB","cpu":"200.0 m","latencyMax":"0.008 s","duration":"120.0 s","replicas":1,"functionImage":"ghcr.io/volodiapg/giraff:giraff_app","functionLiveName":"app-i0-c200-m256-l8-a6-r59692-d120000","dataFlow":[{"from":{"dataSource":"d132ee95-5368-4bc8-9dfd-227eb77da5fc"},"to":"thisFunction"}],"envVars":[["RELEASE_COOKIE","77744409"],["MARKET_URL","131.254.100.55:30008"]],"envProcess":"server","inputMaxSize":"0.000128 MB"})

# sla = Jason.decode!(sla)

get_duration = fn ->
  default_duration = :timer.minutes(2)

  case {paid_at, sla} do
    {nil, nil} ->
      IO.puts("Duration: (default) #{default_duration}")
      default_duration

    {paid_at, %{"duration" => duration_str}} ->
      case String.trim_trailing(duration_str, " s") do
        ^duration_str ->
          IO.puts("Duration: (default) #{default_duration}")
          default_duration

        duration_num_str ->
          to_add = Kernel.trunc(String.to_float(duration_num_str))

          duration =
            DateTime.diff(
              DateTime.add(paid_at, to_add, :second),
              DateTime.utc_now(),
              :millisecond
            )

          if duration < 0 do
            raise "Duration is negative"
          end

          IO.puts("Duration: #{duration}")

          duration
      end

    _ ->
      IO.puts("Duration: (default) #{default_duration}")
      default_duration
  end
end

case config_env() do
  :prod ->
    config :flame, :terminator, log: :debug
    config :flame, :backend, FLAME.GiraffBackend

    for {backend_type, config} <- backend_configs do
      config = Map.merge(config, common_backend_settings)
      config_key = :"#{backend_type}"

      backend_config = {
        FLAME.GiraffBackend,
        duration: get_duration,
        name: config.name,
        market: System.get_env("MARKET_URL"),
        boot_timeout: :timer.minutes(2),
        image: config.image,
        millicpu: config.millicpu,
        memory_mb: config.memory_mb,
        latency_max_ms: config.latency_max_ms,
        target_entrypoint: System.get_env("GIRAFF_NODE_ID"),
        from: System.get_env("GIRAFF_NODE_ID"),
        env: config.env
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
      config = Map.merge(config, common_backend_settings)
      config_key = :"#{backend_type}"

      backend_config = {
        FLAME.DockerBackend,
        name: config.name,
        host: Application.get_env(:giraff, :docker_host),
        boot_timeout: 120_000,
        image: config.image,
        millicpu: config.millicpu,
        memory_mb: config.memory_mb,
        env: config.env
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

  :dev ->
    config :flame, :backend, FLAME.CostTestBackend

    for {backend_type, config} <- backend_configs do
      config = Map.merge(config, common_backend_settings)
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

  :test ->
    config :flame, :backend, FLAME.LocalBackend

    for {backend_type, _config} <- backend_configs do
      config_key = :"#{backend_type}"

      config :giraff, config_key, nil
    end
end
