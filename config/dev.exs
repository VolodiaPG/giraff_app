import Config
# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# config :flame, :backend, FLAME.LocalBackend
config :flame, :backend, FLAME.GiraffBackend

# config :flame, FLAME.LocalBackend, boot_timeout: 120_000

config :flame, :terminator, log: :debug
