defmodule FLAME.MicroVMBackend do
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

  alias Swoosh.Adapters.Local.Storage.Memory
  alias FLAME.MicroVMBackend

  require Logger

  @derive {Inspect,
           only: [
             :host,
             :init,
             :memory_mb,
             :image,
             :app,
             :local_ip,
             :remote_terminator_pid,
             :runner_id,
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

    default = %MicroVMBackend{
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

    %MicroVMBackend{} = state = Map.merge(default, Map.new(provided_opts))

    for key <- [:image, :host, :app] do
      unless Map.get(state, key) do
        raise ArgumentError, "missing :#{key} config for #{inspect(__MODULE__)}"
      end
    end

    suffix = "#{rand_id(14)}"
    state = %MicroVMBackend{state | runner_node_base: "flame-#{suffix}"}
    parent_ref = make_ref()

    encoded_parent =
      parent_ref
      |> FLAME.Parent.new(self(), __MODULE__, state.runner_node_base, "FLY_PRIVATE_IP")
      |> FLAME.Parent.encode()

    new_env =
      %{
        "SECRET_KEY_BASE" => System.get_env("SECRET_KEY_BASE"),
        "FLY_APP_NAME" => "flame",
        "FLY_IMAGE_REF" => suffix,
        "PHX_SERVER" => "false",
        "FLAME_PARENT" => encoded_parent,
        "RELEASE_COOKIE" => Node.get_cookie(),
        "DATABASE_URL" => System.get_env("REMOTE_DATABASE_URL"),
        "ECTO_IPV6" => System.get_env("ECTO_IPV6", "false")
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
      %MicroVMBackend{state | env: new_env, parent_ref: parent_ref, local_ip: ip}

    {:ok, new_state}
  end

  @impl true
  # TODO explore spawn_request
  def remote_spawn_monitor(%MicroVMBackend{} = state, term) do
    Logger.debug("spawning a monitor")

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
    Logger.debug("shutting down")
    System.stop()
  end

  def with_elapsed_ms(func) when is_function(func, 0) do
    {micro, result} = :timer.tc(func)
    {result, div(micro, 1000)}
  end

  def wait_till_pong(_, :pong) do
    :ok
  end

  def wait_till_pong(runner_node_name, :pang) do
    :timer.sleep(100)
    wait_till_pong(runner_node_name, Node.ping(runner_node_name))
  end

  @impl true
  def remote_boot(%MicroVMBackend{parent_ref: parent_ref} = state) do
    {resp, req_connect_time} =
      with_elapsed_ms(fn ->
        env = state.env |> Map.to_list() |> Enum.map(fn {x, y} -> "#{x}='#{y}'" end)

        {resp, status} =
          System.cmd(
            "vm_deploy",
            [state.host, state.runner_node_base] ++ env
          )

        if status != 0 do
          Logger.error("failed to start the microvm to #{state.host} with: #{resp}")
          exit(:error)
        end

        container_id = state.runner_node_base
        Logger.debug("Started (async) #{state.runner_node_base}")
        private_runner_ip = container_id

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
          %MicroVMBackend{
            state
            | runner_id: container_id,
              runner_private_ip: private_runner_ip
          }

        remote_terminator_pid =
          receive do
            {^parent_ref, {:remote_up, remote_terminator_pid}} ->
              remote_terminator_pid
          after
            remaining_connect_window ->
              Logger.error("failed to connect to fly machine within #{state.boot_timeout} ms")
              exit(:timeout)
          end

        new_state = %MicroVMBackend{
          new_state
          | remote_terminator_pid: remote_terminator_pid,
            runner_node_name: node(remote_terminator_pid)
        }

        # {resp, req_connect_time} =
        #  with_elapsed_ms(fn -> wait_till_pong(new_state.runner_node_name, :pang) end)

        # remaining_connect_window = remaining_connect_window - req_connect_time

        # IO.inspect(resp)

        # case resp do
        #  :ok ->
        #    Logger.debug(
        #      "All good for #{new_state.runner_node_base}, now going onto the next steps with node name #{new_state.runner_node_name}"
        #    )

        #    {:ok, remote_terminator_pid, new_state}

        #  other ->
        #    {:error, other}
        # end

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
end
