defmodule FLAME.GiraffBackend do
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

  * `:cpus` - The number of runner CPUs. Defaults to  `System.schedulers_online()`
    for the number of cores of the running parent app.

  * `:memory_mb` - The memory of the runner. Must be a 1024 multiple. Defaults to `4096`.

  * `:boot_timeout` - The boot timeout. Defaults to `30_000`.

  * `:app` – The name of the otp app. Defaults to `System.get_env("FLY_APP_NAME")`,

  * `:image` – The URL of the docker image to pass to the machines create endpoint.
    Defaults to `System.get_env("FLY_IMAGE_REF")` which is the image of your running app.

  * `:token` – The Fly API token. Defaults to `System.get_env("FLY_API_TOKEN")`.

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
  alias FLAME.GiraffBackend

  require Logger

  @derive {Inspect,
           only: [
             :market,
             :init,
             :memory_mb,
             :millicpu,
             :duration,
             :livename,
             :max_replica,
             :latency_max_ms,
             :from,
             :input_max_size_mb,
             :target_entrypoint,
             :image,
             :local_ip,
             :remote_terminator_pid,
             :faas_ip,
             :faas_id,
             :faas_port,
             :function_id,
             :boot_timeout
           ]}
  defstruct market: nil,
            init: %{},
            local_ip: nil,
            env: %{},
            memory_mb: nil,
            millicpu: nil,
            duration: nil,
            livename: nil,
            max_replica: 1,
            latency_max_ms: nil,
            from: nil,
            target_entrypoint: nil,
            input_max_size_mb: nil,
            image: nil,
            services: [],
            boot_timeout: nil,
            runner_id: nil,
            remote_terminator_pid: nil,
            parent_ref: nil,
            faas_ip: nil,
            faas_id: nil,
            faas_port: nil,
            function_id: nil,
            log: nil,
            runner_node_name: nil

  @valid_opts [
    :app,
    :image,
    :market,
    :init,
    :memory_mb,
    :boot_timeout,
    :env,
    :terminator_sup,
    :log,
    :services,
    :millicpu,
    :duration,
    :livename,
    :max_replica,
    :latency_max_ms,
    :from,
    :input_max_size_mb,
    :target_entrypoint
  ]

  @impl true
  def init(opts) do
    conf = Application.get_env(:flame, __MODULE__) || []
    [_node_base, ip] = node() |> to_string() |> String.split("@")

    # Logger.debug("node is #{node()}")

    default = %GiraffBackend{
      memory_mb: 256,
      millicpu: 1000,
      boot_timeout: 120_000,
      max_replica: 1,
      input_max_size_mb: 1024,
      duration: 120_000,
      services: [],
      init: [],
      log: Keyword.get(conf, :log, false)
    }

    provided_opts =
      conf
      |> Keyword.merge(opts)
      |> Keyword.validate!(@valid_opts)

    %GiraffBackend{} = state = Map.merge(default, Map.new(provided_opts))

    for key <- [:image, :market, :latency_max_ms, :target_entrypoint] do
      unless Map.get(state, key) do
        raise ArgumentError, "missing :#{key} config for #{inspect(__MODULE__)}"
      end
    end

    suffix = "#{rand_id(14)}"
    state = %GiraffBackend{state | livename: "flame-#{suffix}"}
    parent_ref = make_ref()

    encoded_parent =
      parent_ref
      |> FLAME.Parent.new(self(), __MODULE__, state.livename, "PRIVATE_IP")
      |> FLAME.Parent.encode()

    Logger.debug("Flame parent: #{encoded_parent}")

    new_env =
      %{
        "SECRET_KEY_BASE" => System.get_env("SECRET_KEY_BASE"),
        # "PRIVATE_IP" => "131.254.100.55",
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
      %GiraffBackend{state | env: new_env, parent_ref: parent_ref, local_ip: ip}

    {:ok, new_state}
  end

  @impl true
  # TODO explore spawn_request
  def remote_spawn_monitor(%GiraffBackend{} = state, term) do
    Logger.debug("spawning a monitor on #{state.runner_node_name}")

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
  def remote_boot(%GiraffBackend{parent_ref: parent_ref} = state) do
    {resp, req_connect_time} =
      with_elapsed_ms(fn ->
        env = state.env |> Map.to_list() |> Enum.map(fn {x, y} -> ["#{x}","#{y}"] end)

        res =
          Req.put!(
            "http://#{state.market}/api/function",
            connect_options: [timeout: state.boot_timeout],
            json: %{
              sla: %{
                memory: "#{state.memory_mb} MB",
                cpu: "#{state.millicpu} millicpu",
                latencyMax: "#{state.latency_max_ms} ms",
                replicas: state.max_replica,
                duration: "#{state.duration} ms",
                functionImage: state.image,
                functionLiveName: state.livename,
                envVars: env,
                envProcess: "function",
                dataFlow: [
                  %{
                    from: %{dataSource: state.from},
                    to: "thisFunction"
                  }
                ],
                inputMaxSize: "#{state.input_max_size_mb} MB"
              },
              targetNode: state.target_entrypoint
            }
          )

        if res.status != 200 do
          Logger.error(
            "failed to reserve the giraff function to #{state.market} with: #{res.body}"
          )

          exit(:error)
        end

        faas_ip = Kernel.get_in(res.body, ["chosen", "ip"])
        faas_id = Kernel.get_in(res.body, ["chosen", "bid", "nodeId"])
        faas_port = Kernel.get_in(res.body, ["chosen", "port"])
        function_id = Kernel.get_in(res.body, ["sla", "id"])

        res = Req.post!(
          "http://#{state.market}/api/function/#{function_id}",
          connect_options: [timeout: state.boot_timeout],
          receive_timeout: state.boot_timeout,
          body: nil
        )

        if res.status != 200 do
          Logger.error("failed to start the giraff function on #{state.market} with: #{res}")

          exit(:error)
        end

        Logger.debug("Started (async) #{function_id} on #{faas_id} (#{faas_ip}:#{faas_port})")

        {:ok, faas_ip, faas_port, faas_id, function_id}
      end)

    if state.log,
      do:
        Logger.log(
          state.log,
          "#{inspect(__MODULE__)} #{inspect(node())} machine create #{req_connect_time}ms"
        )

    remaining_connect_window = state.boot_timeout - req_connect_time

    case resp do
      {:ok, faas_ip, faas_port, faas_id, function_id} ->
        new_state =
          %GiraffBackend{
            state
            | faas_id: faas_id,
              faas_ip: faas_ip,
              faas_port: faas_port,
              function_id: function_id
          }

        remote_terminator_pid =
          receive do
            {^parent_ref, {:remote_up, remote_terminator_pid}} ->
              remote_terminator_pid
          after
            remaining_connect_window ->
              Logger.error("failed to connect to Giraff machine within #{state.boot_timeout} ms")
              exit(:timeout)
          end

        new_state = %GiraffBackend{
          new_state
          | remote_terminator_pid: remote_terminator_pid,
            runner_node_name: node(remote_terminator_pid)
        }

        Logger.debug("successed to connect to Giraff machine #{new_state.runner_node_name} within #{state.boot_timeout} ms")

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
