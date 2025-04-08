import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.

# We don't run a server during test. If one is required,
# you can enable the server option below.

# In test we don't send emails.

# Print only warnings and errors during test

config :flame, :terminator, log: :debug

config :flame, :backend, FLAME.LocalBackend

config :logger,
  backends: [
    :console
  ]
