defmodule FLAME.NodeBackend do
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

    * `:gpu_kind` - The type of GPU reservation to make`.

    * `:cpus` - The number of runner CPUs. Defaults to  `System.schedulers_online()`
      for the number of cores of the running parent app.

    * `:memory_mb` - The memory of the runner. Must be a 1024 multiple. Defaults to `4096`.

    * `:boot_timeout` - The boot timeout. Defaults to `30_000`.

    * `:app` – The name of the otp app. Defaults to `System.get_env("FLY_APP_NAME")`,

    * `:image` – The URL of the docker image to pass to the machines create endpoint.
      Defaults to `System.get_env("FLY_IMAGE_REF")` which is the image of your running app.

    * `:token` – The Fly API token. Defaults to `System.get_env("FLY_API_TOKEN")`.

    * `:host` – The host of the Fly API. Defaults to `"https://api.machines.dev"`.

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

  alias FLAME.NodeBackend

  require Logger

  @derive {Inspect,
           only: [
             :host,
             :cpus,
             :gpu_kind,
             :memory_mb,
             :image,
             :app,
             :container_id,
             :container_name,
             :container_ip,
             :local_ip,
             :remote_terminator_pid,
             :runner_node_basename,
             :runner_node_name,
             :boot_timeout,
             :tailscale_authkey
           ]}
  defstruct host: nil,
            local_ip: nil,
            env: %{},
            cpus: nil,
            memory_mb: nil,
            gpu_kind: nil,
            image: nil,
            services: [],
            metadata: %{},
            app: nil,
            tailscale_authkey: nil,
            boot_timeout: nil,
            container_id: nil,
            container_name: nil,
            container_ip: nil,
            remote_terminator_pid: nil,
            parent_ref: nil,
            runner_node_basename: nil,
            runner_node_name: nil,
            log: nil

  @valid_opts [
    :app,
    :tailscale_authkey,
    :cpus,
    :memory_mb,
    :gpu_kind,
    :boot_timeout,
    :env,
    :terminator_sup,
    :log,
    :services,
    :metadata
  ]

  @impl true
  def init(opts) do
    conf = Application.get_env(:flame, __MODULE__) || []
    [node_base, ip] = node() |> to_string() |> String.split("@")

    default = %NodeBackend{
      app: "toto",
      image: "ghcr.io/volodiapg/thumbs:latest",
      host: "http://localhost-0:12345",
      cpus: System.schedulers_online(),
      memory_mb: 256,
      boot_timeout: 30_000,
      runner_node_basename: node_base,
      services: [],
      metadata: %{},
      log: Keyword.get(conf, :log, false)
    }

    provided_opts =
      conf
      |> Keyword.merge(opts)
      |> Keyword.validate!(@valid_opts)

    state = Map.merge(default, Map.new(provided_opts))

    for key <- [:image, :host, :app] do
      unless Map.get(state, key) do
        raise ArgumentError, "missing :#{key} config for #{inspect(__MODULE__)}"
      end
    end

    parent_ref = make_ref()

    encoded_parent =
      parent_ref
      |> FLAME.Parent.new(self(), __MODULE__)
      |> FLAME.Parent.encode()

    secret_key_base =
      :crypto.strong_rand_bytes(64)
      |> Base.encode64(padding: false)
      |> binary_part(0, 64)

    new_env =
      Map.merge(
        %{
          "PHX_SERVER" => false,
          "FLAME_PARENT" => encoded_parent,
          "RELEASE_COOKIE" => Node.get_cookie(),
          "DATABASE_URL" => System.get_env("DATABASE_URL"),
          "SECRET_KEY_BASE" => System.get_env("SECRET_KEY_BASE"),
          "TAILSCALE_AUTHKEY" => state.tailscale_authkey,
          "MIX_ENV" => "prod"
        },
        state.env
      )

    new_state =
      %NodeBackend{state | env: new_env, parent_ref: parent_ref, local_ip: ip}

    {:ok, new_state}
  end

  @impl true
  # TODO explore spawn_request
  def remote_spawn_monitor(%NodeBackend{} = state, term) do
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
  def remote_boot(%NodeBackend{parent_ref: parent_ref} = state) do
    {res, req_connect_time} =
      with_elapsed_ms(fn ->
        res =
          Req.post!(
            "#{state.host}/v1.43/images/create?fromImage=#{state.image}",
            connect_options: [timeout: state.boot_timeout],
            into: IO.stream()
          )

        if res.status != 200 do
          raise "Failed to pull image with data:" <> res.data
        end

        postfix = rand_id(20)

        container_name = "#{state.app}-flame-#{postfix}"
        container_ip = state.host |> URI.parse() |> Map.fetch!(:host)

        env =
          Map.merge(
            %{
              "FLY_APP_NAME" => "#{state.app}-flame",
              "FLY_IMAGE_REF" => "#{postfix}",
              "FLY_PRIVATE_IP" => "#{container_ip}"
              # FLY_APP_NAME: "#{System.get_env("FLY_APP_NAME")}",
              # FLY_IMAGE_REF: "#{System.get_env("FLY_IMAGE_REF")}",
              # FLY_PRIVATE_IP: "#{System.get_env("FLY_PRIVATE_IP")}"
            },
            state.env
          )

        env = env |> Map.to_list() |> Enum.map(fn {x, y} -> "#{x}=#{y}" end)

        res =
          Req.post!("#{state.host}/v1.43/containers/create",
            connect_options: [timeout: state.boot_timeout],
            json: %{
              Hostname: container_name,
              Image: state.image,
              Env: env,
              # Cmd: ["thumbs", "start"],
              Cmd: ["server"],
              # Cmd: [
              #  "server",
              #  "-name",
              #  "#{state.app}",
              #  "-user",
              #  "nobody"
              # ],
              # Volumes: %{
              #  "/dev/net/tun": %{}
              # },
              HostConfig: %{
                # CapAdd: [
                #  "NET_ADMIN",
                #  "SYS_MODULE"
                # ],
                Memory: state.memory_mb * 1024 * 1024,
                # Dns: [
                #  "1.1.1.1"
                # ],
                NetworkMode: "host"
                # Binds: [
                #  "/dev/net/tun1:/dev/net/tun"
                # ]
              }
            }
          )

        container_id = Map.fetch!(res.body, "Id")

        Req.post!(
          "#{state.host}/v1.43/containers/#{container_id}/start",
          connect_options: [timeout: state.boot_timeout]
        )

        {:ok, container_id, container_name, "127.0.0.1"}
      end)

    if state.log,
      do:
        Logger.log(
          state.log,
          "#{inspect(__MODULE__)} #{inspect(node())} machine create #{req_connect_time}ms"
        )

    remaining_connect_window = state.boot_timeout - req_connect_time

    case res do
      {:ok, container_id, container_name, container_ip} ->
        new_state =
          %NodeBackend{
            state
            | container_id: container_id,
              container_name: container_name,
              container_ip: container_ip,
              runner_node_name: :"#{state.runner_node_basename}@#{container_ip}"
          }

        remote_terminator_pid =
          receive do
            {^parent_ref, {:remote_up, remote_terminator_pid}} ->
              remote_terminator_pid
          after
            remaining_connect_window ->
              Logger.error("failed to connect to fly machine within #{state.boot_timeout}ms")
              exit(:timeout)
          end

        new_state = %NodeBackend{new_state | remote_terminator_pid: remote_terminator_pid}
        {:ok, remote_terminator_pid, new_state}

      other ->
        {:error, other}
    end
  end

  defp rand_id(len) do
    len
    |> :crypto.strong_rand_bytes()
    |> Base.encode64(padding: false)
    |> binary_part(0, len)
    |> String.replace("/", "")
    |> String.replace("+", "")
  end
end
