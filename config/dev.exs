import Config
# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

config :flame, :terminator, log: :debug

config :flame, :backend, FLAME.LocalBackend

config :giraff, speech_to_text_backend: FLAME.LocalBackend

config :giraff, text_to_speech_backend: FLAME.LocalBackend

config :giraff, end_game_backend: FLAME.LocalBackend

config :giraff, sentiment_backend: FLAME.LocalBackend
