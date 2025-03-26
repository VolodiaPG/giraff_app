# Thumbs

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix


## Digrams

```elixir
# config/runtime.exs
config :giraff,
       :speech_to_text_backend,
       {FLAME.Pool,
        [
          name: Giraff.SpeechToTextBackend,
          min: 1, max: 100, max_concurrency: 4,
          single_use: false,
          backend: {
            FLAME.GiraffBackend,
            image: "ghcr.io/...", millicpu: 1000, memory_mb: 1024
          }
        ]
       }

# application.ex
children =
      children(
        ...,
        parent: @speech_to_text_backend_config,
        ...
      )
{:ok, sup} = Supervisor.start_link(children, ...)

# endpoint.ex
def my_function(param) do
  "I'm a giraff, #{param}"
end

post "/" do
 param = conn.body_params["param"]
 result = FLAME.call(Giraff.SpeechToTextBackend, fn -> my_function(param) end)
 send_resp(conn, 200, result)
end
```

