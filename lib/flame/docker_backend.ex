defmodule FLAME.DockerBackend do
  @moduledoc """
  A `FLAME.Backend` using [Fly.io](https://fly.io) machines.

  The only required configuration is telling FLAME to use the
  `FLAME.FlyBackend` by default and the `:token` which is your Fly.io API
  token. These can be set via application configuration in your `config/runtime.exs`
  withing a `:prod` block:

      if config_env() == :prod do
        config :flame, :backend, FLAME.FlyBackend
        config :flame, FLAME.FlyBackend, token: System.fetch_env!("FLY_API_TOKEN")
        ...
      end

  To set your `FLY_API_TOKEN` secret, you can run the following commands locally:

  ```bash
  $ fly secrets set FLY_API_TOKEN="$(fly auth token)"
  ```

  The following backend options are supported, and mirror the
  [Fly.io machines create API](https://fly.io/docs/machines/api/machines-resource/#machine-config-object-properties):

  * `:cpu_kind` - The size of the runner CPU. Defaults to `"performance"`.

  * `:gpu_kind` - The type of GPU reservation to make.

  * `:cpus` - The number of runner CPUs. Defaults to  `System.schedulers_online()`
    for the number of cores of the running parent app.

  * `:memory_mb` - The memory of the runner. Must be a 1024 multiple. Defaults to `4096`.

  * `:boot_timeout` - The boot timeout. Defaults to `30_000`.

  * `:app` – The name of the otp app. Defaults to `System.get_env("FLY_APP_NAME")`,

  * `:image` – The URL of the docker image to pass to the machines create endpoint.
    Defaults to `System.get_env("FLY_IMAGE_REF")` which is the image of your running app.

  * `:token` – The Fly API token. Defaults to `System.get_env("FLY_API_TOKEN")`.

  * `:host` – The host of the Fly API. Defaults to `"https://api.machines.dev"`.

  * `:init` – The init object to pass to the machines create endpoint. Defaults to `%{}`.
    Possible values include:

      * `:cmd` – list of strings for the command
      * `:entrypoint` – list strings for the entrypoint command
      * `:exec` – list of strings for the exec command
      * `:kernel_args` - list of strings
      * `:swap_size_mb` – integer value in megabytes for th swap size
      * `:tty` – boolean

  * `:services` - The optional services to run on the machine. Defaults to `[]`.

  * `:metadata` - The optional map of metadata to set for the machine. Defaults to `%{}`.

  ## Environment Variables

  The FLAME Fly machines do *do not* inherit the environment variables of the parent.
  You must explicit provide the environment that you would like to forward to the
  machine. For example, if your FLAME's are starting your Ecto repos, you can copy
  the env from the parent:

  ```elixir
  config :flame, FLAME.FlyBackend,
    token: System.fetch_env!("FLY_API_TOKEN"),
    env: %{
      "DATABASE_URL" => System.fetch_env!("DATABASE_URL")
      "POOL_SIZE" => "1"
    }
  ```

  Or pass the env to each pool:

  ```elixir
  {FLAME.Pool,
    name: MyRunner,
    backend: {FLAME.FlyBackend, env: %{"DATABASE_URL" => System.fetch_env!("DATABASE_URL")}}
  }
  ```
  """
  @behaviour FLAME.Backend

  alias FLAME.DockerBackend

  require Logger

  @derive {Inspect,
           only: [
             :host,
             :init,
             :memory_mb,
             :image,
             :app,
             :runner_id,
             :local_ip,
             :remote_terminator_pid,
             :runner_instance_id,
             :runner_private_ip,
             :runner_node_base,
             :runner_node_name,
             :boot_timeout
           ]}
  defstruct host: nil,
            init: %{},
            local_ip: nil,
            env: %{},
            memory_mb: nil,
            gpu_kind: nil,
            image: nil,
            services: [],
            app: nil,
            boot_timeout: nil,
            runner_id: nil,
            remote_terminator_pid: nil,
            parent_ref: nil,
            runner_instance_id: nil,
            runner_private_ip: nil,
            runner_node_base: nil,
            runner_node_name: nil,
            log: nil

  @valid_opts [
    :app,
    :image,
    :host,
    :init,
    :memory_mb,
    :boot_timeout,
    :env,
    :terminator_sup,
    :log,
    :services
  ]

  @impl true
  def init(opts) do
    conf = Application.get_env(:flame, __MODULE__) || []
    [_node_base, ip] = node() |> to_string() |> String.split("@")

    default = %DockerBackend{
      app: System.get_env("FLY_APP_NAME"),
      image: System.get_env("FLY_IMAGE"),
      host: System.get_env("FLY_HOST"),
      memory_mb: 256,
      boot_timeout: 120_000,
      services: [],
      init: [],
      log: Keyword.get(conf, :log, false)
    }

    provided_opts =
      conf
      |> Keyword.merge(opts)
      |> Keyword.validate!(@valid_opts)

    %DockerBackend{} = state = Map.merge(default, Map.new(provided_opts))

    for key <- [:image, :host, :app] do
      unless Map.get(state, key) do
        raise ArgumentError, "missing :#{key} config for #{inspect(__MODULE__)}"
      end
    end

    suffix = "#{rand_id(20)}"
    state = %DockerBackend{state | runner_node_base: "#{state.app}-flame-#{suffix}"}
    parent_ref = make_ref()

    encoded_parent =
      parent_ref
      |> FLAME.Parent.new(self(), __MODULE__, state.runner_node_base, "FLY_PRIVATE_IP")
      |> FLAME.Parent.encode()

    secret_key_base =
      :crypto.strong_rand_bytes(64)
      |> Base.encode64(padding: false)
      |> binary_part(0, 64)

    new_env =
      %{
        "SECRET_KEY_BASE" => System.get_env("SECRET_KEY_BASE"),
        # "FLY_PRIVATE_IP" => System.get_env("FLY_PRIVATE_IP"),
        "FLY_APP_NAME" => "#{state.app}-flame",
        "FLY_IMAGE_REF" => suffix,
        "PHX_SERVER" => "false",
        "FLAME_PARENT" => encoded_parent,
        "RELEASE_COOKIE" => Node.get_cookie()
      }
      |> Map.merge(state.env)
      |> then(fn env ->
        if flags = System.get_env("ERL_AFLAGS") do
          Map.put_new(env, "ERL_AFLAGS", flags)
        else
          env
        end
      end)
      |> then(fn env ->
        if flags = System.get_env("ERL_ZFLAGS") do
          Map.put_new(env, "ERL_ZFLAGS", flags)
        else
          env
        end
      end)

    new_state =
      %DockerBackend{state | env: new_env, parent_ref: parent_ref, local_ip: ip}

    {:ok, new_state}
  end

  @impl true
  # TODO explore spawn_request
  def remote_spawn_monitor(%DockerBackend{} = state, term) do
    case term do
      func when is_function(func, 0) ->
        {pid, ref} = Node.spawn_monitor(state.runner_node_name, func)
        {:ok, {pid, ref}}

      {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
        {pid, ref} = Node.spawn_monitor(state.runner_node_name, mod, fun, args)
        {:ok, {pid, ref}}

      other ->
        raise ArgumentError,
              "expected a null arity function or {mod, func, args}. Got: #{inspect(other)}"
    end
  end

  @impl true
  def system_shutdown do
    System.stop()
  end

  def with_elapsed_ms(func) when is_function(func, 0) do
    {micro, result} = :timer.tc(func)
    {result, div(micro, 1000)}
  end

  @impl true
  def remote_boot(%DockerBackend{parent_ref: parent_ref} = state) do
    {resp, req_connect_time} =
      with_elapsed_ms(fn ->
        http_post!("#{state.host}/v1.43/images/create?fromImage=#{state.image}",
          connect_timeout: state.boot_timeout,
          content_type: "text/plain",
          headers: [
            {"Content-Type", "text/plain"}
          ],
          body: ""
        )

        env = state.env |> Map.to_list() |> Enum.map(fn {x, y} -> "#{x}=#{y}" end)

        body =
          http_post!("#{state.host}/v1.43/containers/create",
            content_type: "application/json",
            headers: [
              {"Content-Type", "application/json"}
            ],
            connect_timeout: state.boot_timeout,
            body:
              Jason.encode!(%{
                Hostname: state.runner_node_base,
                Image: state.image,
                Env: env,
                Cmd: ["entrypoint", "thumbs", "start"],
                HostConfig: %{
                  # NetworkMode: "host",
                  #  Binds: [
                  #    "/var/run/tailscale/tailscaled.sock:/var/run/tailscale/tailscaled.sock"
                  #  ],
                  Memory: state.memory_mb * 1024 * 1024
                }
              })
          )

        container_id = Map.fetch!(Jason.decode!(body), "Id")

        http_post!("#{state.host}/v1.43/containers/#{container_id}/start",
          connect_timeout: state.boot_timeout,
          content_type: "text/plain",
          headers: [
            {"Content-Type", "text/plain"}
          ],
          body: ""
        )

        body =
          http_post!("#{state.host}/v1.43/containers/#{container_id}/exec",
            connect_timeout: state.boot_timeout,
            content_type: "application/json",
            headers: [
              {"Content-Type", "application/json"}
            ],
            body:
              Jason.encode!(%{
                AttachStdout: true,
                Cmd: ["node_name", "--json"]
              })
          )

        exec_id = Map.fetch!(Jason.decode!(body), "Id")

        body =
          http_post!("#{state.host}/v1.43/exec/#{exec_id}/start",
            connect_timeout: state.boot_timeout,
            content_type: "application/json",
            headers: [
              {"Content-Type", "application/json"}
            ],
            body:
              Jason.encode!(%{
                Tty: true
              })
          )

        private_runner_ip = Map.fetch!(Jason.decode!(body), "Ip")

        {:success, container_id, private_runner_ip}
      end)

    if state.log,
      do:
        Logger.log(
          state.log,
          "#{inspect(__MODULE__)} #{inspect(node())} machine create #{req_connect_time}ms"
        )

    remaining_connect_window = state.boot_timeout - req_connect_time

    case resp do
      {:success, container_id, private_runner_ip} ->
        new_state =
          %DockerBackend{
            state
            | runner_instance_id: container_id,
              runner_private_ip: private_runner_ip,
              runner_node_name: :"#{state.runner_node_base}@#{private_runner_ip}"
          }

        if state.log,
          do:
            Logger.log(
              state.log,
              "#{inspect(__MODULE__)} remote node is #{new_state.runner_node_name}"
            )

        remote_terminator_pid =
          receive do
            {^parent_ref, {:remote_up, remote_terminator_pid}} ->
              remote_terminator_pid
          after
            remaining_connect_window ->
              Logger.error("failed to connect to fly machine within #{state.boot_timeout} ms")
              exit(:timeout)
          end

        new_state = %DockerBackend{
          new_state
          | remote_terminator_pid: remote_terminator_pid
        }

        {:ok, remote_terminator_pid, new_state}

      other ->
        {:error, other}
    end
  end

  defp rand_id(len) do
    len
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
    |> binary_part(0, len)
  end

  defp http_post!(url, opts) do
    Keyword.validate!(opts, [:headers, :body, :connect_timeout, :content_type])

    headers =
      for {field, val} <- Keyword.fetch!(opts, :headers),
          do: {String.to_charlist(field), val}

    body = Keyword.fetch!(opts, :body)
    connect_timeout = Keyword.fetch!(opts, :connect_timeout)
    content_type = Keyword.fetch!(opts, :content_type)

    http_opts = [
      ssl:
        [
          verify: :verify_peer,
          depth: 2,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ] ++ cacerts_options(),
      connect_timeout: connect_timeout
    ]

    case :httpc.request(:post, {url, headers, ~c"#{content_type}", body}, http_opts, []) do
      {:ok, {{_, status, _}, _, response_body}} when status in 200..299 ->
        response_body

      {:ok, {{_, status, reason}, _, resp_body}} ->
        raise "failed POST #{url} with #{inspect(status)} (#{inspect(reason)}): #{inspect(resp_body)} #{inspect(headers)}"

      {:error, reason} ->
        raise "failed POST #{url} with #{inspect(reason)} #{inspect(headers)}"
    end
  end

  defp cacerts_options do
    cond do
      certs = otp_cacerts() ->
        [cacerts: certs]

      Application.spec(:castore, :vsn) ->
        [cacertfile: Application.app_dir(:castore, "priv/cacerts.pem")]

      true ->
        IO.warn("""
        No certificate trust store was found.

        A certificate trust store is required in
        order to download locales for your configuration.
        Since elixir_make could not detect a system
        installed certificate trust store one of the
        following actions may be taken:

        1. Use OTP 25+ on an OS that has built-in certificate
           trust store.

        2. Install the hex package `castore`. It will
           be automatically detected after recompilation.

        """)

        []
    end
  end

  if System.otp_release() >= "25" do
    defp otp_cacerts do
      :public_key.cacerts_get()
    rescue
      _ -> nil
    end
  else
    defp otp_cacerts, do: nil
  end
end
