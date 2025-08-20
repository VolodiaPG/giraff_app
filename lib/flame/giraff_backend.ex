defmodule FLAME.GiraffBackend do
  @moduledoc """
  A `FLAME.Backend` using [Giraff](https://github.com/volodiapg/giraff) machines.
  ```
  """
  @behaviour FLAME.Backend

  alias FLAME.GiraffBackend

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  require OpenTelemetry.Ctx, as: Ctx

  @derive {Inspect,
           only: [
             :name,
             :market,
             :init,
             :memory_mb,
             :millicpu,
             :duration,
             :livename,
             :max_replica,
             :latency_max_ms,
             :from,
             :input_max_size_b,
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
  defstruct name: nil,
            market: nil,
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
            input_max_size_b: nil,
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
            runner_node_name: nil,
            on_accepted_offer: nil,
            on_new_boot: nil

  @valid_opts [
    :name,
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
    :input_max_size_b,
    :target_entrypoint,
    :on_accepted_offer,
    :on_new_boot
  ]

  @impl true
  def init(opts) do
    conf = Application.get_env(:flame, __MODULE__) || []
    [_node_base, ip] = node() |> to_string() |> String.split("@")

    default = %GiraffBackend{
      memory_mb: 256,
      millicpu: 1000,
      boot_timeout: 30_000,
      max_replica: 1,
      input_max_size_b: 1,
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

    for key <- [:image, :market, :latency_max_ms, :target_entrypoint, :from, :name] do
      unless Map.get(state, key) do
        raise ArgumentError, "missing :#{key} config for #{inspect(__MODULE__)}"
      end
    end

    livename = "#{state.name}_#{rand_id(8)}"
    state = %GiraffBackend{state | livename: livename}
    parent_ref = make_ref()

    Logger.info("Creating parent for #{state.name} with livename #{state.livename}")

    encoded_parent =
      parent_ref
      |> FLAME.Parent.new(self(), __MODULE__, state.livename, "PRIVATE_IP")
      |> FLAME.Parent.encode()

    Logger.debug("Flame parent: #{encoded_parent}")

    new_env =
      %{
        "SECRET_KEY_BASE" => Application.get_env(:giraff, :secret_key_base),
        "OTEL_NAMESPACE" => Application.get_env(:flame, :otel_namespace),
        "FLAME_PARENT" => encoded_parent,
        "MARKET_URL" => state.market,
        "RELEASE_COOKIE" => Node.get_cookie(),
        "MIX_ENV" => Application.get_env(:giraff, Giraff.Application)[:env],
        "DOCKER_REGISTRY" => Application.get_env(:giraff, :docker_registry)
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

    Tracer.with_span "spawn_monitor" do
      Tracer.set_attribute("runner_node_name", state.runner_node_name)

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
    if state.on_new_boot, do: state.on_new_boot.(%{name: state.name})

    {resp, req_connect_time} =
      with_elapsed_ms(fn ->
        Tracer.with_span "create_machine" do
          env = state.env |> Map.to_list() |> Enum.map(fn {x, y} -> ["#{x}", "#{y}"] end)

          duration =
            if is_function(state.duration, 0) do
              state.duration.()
            else
              state.duration
            end

          sla = %{
            memory: "#{state.memory_mb} MB",
            cpu: "#{state.millicpu} millicpu",
            latencyMax: "#{state.latency_max_ms} ms",
            replicas: state.max_replica,
            duration: "#{duration} ms",
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
            inputMaxSize: "#{state.input_max_size_b} b"
          }

          Tracer.set_attribute("sla", Jason.encode!(sla))

          res =
            Req.put!(
              "http://#{state.market}/api/function",
              connect_options: [timeout: state.boot_timeout],
              json: %{
                sla: sla,
                targetNode: state.target_entrypoint
              }
            )

          case res do
            %{
              status: 200,
              body: %{
                "chosen" => %{
                  "ip" => faas_ip,
                  "bid" => %{"nodeId" => faas_id},
                  "price" => price,
                  "port" => faas_port
                },
                "sla" => %{"id" => function_id}
              }
            } ->
              res =
                Req.post!(
                  "http://#{state.market}/api/function/#{function_id}",
                  connect_options: [timeout: state.boot_timeout],
                  receive_timeout: state.boot_timeout,
                  body: nil
                )

              case res do
                %{status: 200} ->
                  if state.on_accepted_offer,
                    do: state.on_accepted_offer.(%{name: state.name, price: price})

                  {:ok, faas_ip, faas_port, faas_id, function_id}

                _ ->
                  raise "failed to run the paid giraff function to #{state.market} with: #{res.body}"
              end

            _ ->
              raise "failed to reserve the giraff function to #{state.market} with: #{res.body}"
          end
        end
      end)

    if state.log,
      do:
        Logger.log(
          state.log,
          "#{inspect(__MODULE__)} #{inspect(node())} machine create #{req_connect_time}ms"
        )

    remaining_connect_window = state.boot_timeout - req_connect_time

    Tracer.with_span "wait_ack" do
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

          Tracer.set_attribute("faas_ip", faas_ip)
          Tracer.set_attribute("faas_port", faas_port)
          Tracer.set_attribute("faas_id", faas_id)
          Tracer.set_attribute("function_id", function_id)

          remote_terminator_pid =
            receive do
              {^parent_ref, {:remote_up, remote_terminator_pid}} ->
                remote_terminator_pid
            after
              remaining_connect_window ->
                if state.log,
                  do:
                    Logger.error(
                      "failed to connect to Giraff machine within #{state.boot_timeout} ms"
                    )

                exit(:timeout)
            end

          runner_node_name = node(remote_terminator_pid)

          new_state = %GiraffBackend{
            new_state
            | remote_terminator_pid: remote_terminator_pid,
              runner_node_name: runner_node_name
          }

          if state.log,
            do:
              Logger.debug(
                "successed to connect to Giraff machine #{new_state.runner_node_name} within #{state.boot_timeout} ms"
              )

          {:ok, remote_terminator_pid, new_state}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, other}
      end
    end
  end

  defp rand_id(len) do
    len
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
    |> binary_part(0, len)
  end
end
