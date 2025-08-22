defmodule FLAME.DockerBackend do
  @behaviour FLAME.Backend

  alias FLAME.DockerBackend

  require Logger

  @derive {Inspect,
           only: [
             :name,
             :host,
             :init,
             :memory_mb,
             :millicpu,
             :image,
             :runner_id,
             :local_ip,
             :remote_terminator_pid,
             :runner_instance_id,
             :runner_private_ip,
             :runner_node_name,
             :boot_timeout,
             :livename
           ]}
  defstruct name: nil,
            livename: nil,
            host: nil,
            init: %{},
            local_ip: nil,
            env: %{},
            memory_mb: nil,
            millicpu: nil,
            gpu_kind: nil,
            image: nil,
            services: [],
            boot_timeout: nil,
            runner_id: nil,
            remote_terminator_pid: nil,
            parent_ref: nil,
            runner_instance_id: nil,
            runner_private_ip: nil,
            runner_node_name: nil,
            on_new_boot: nil,
            on_accepted_offer: nil,
            log: nil

  @valid_opts [
    :name,
    :image,
    :host,
    :init,
    :millicpu,
    :memory_mb,
    :boot_timeout,
    :env,
    :terminator_sup,
    :log,
    :services,
    :livename,
    :on_new_boot,
    :on_accepted_offer
  ]

  @impl true
  def init(opts) do
    conf = Application.get_env(:flame, __MODULE__) || []

    [_node_base, ip] = node() |> to_string() |> String.split("@")

    default = %DockerBackend{
      host: "http+unix://%2Fvar%2Frun%2Fdocker.sock",
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

    for key <- [:image, :host, :name] do
      unless Map.get(state, key) do
        raise ArgumentError, "missing :#{key} config for #{inspect(__MODULE__)}"
      end
    end

    livename = "#{state.name}_#{rand_id(8)}"
    state = %DockerBackend{state | livename: livename}
    parent_ref = make_ref()

    encoded_parent =
      parent_ref
      |> FLAME.Parent.new(self(), __MODULE__, state.livename, "PRIVATE_IP")
      |> FLAME.Parent.encode()

    new_env =
      %{
        "SECRET_KEY_BASE" => System.get_env("SECRET_KEY_BASE"),
        "OTEL_NAMESPACE" => Application.get_env(:flame, :otel_namespace),
        "OTEL_EXPORTER_OTLP_ENDPOINT_FUNCTION" => Application.get_env(:giraff, :otel_endpoint),
        "FLAME_PARENT" => encoded_parent,
        "RELEASE_COOKIE" => Node.get_cookie(),
        "NAME" => state.livename,
        "MIX_ENV" => Application.get_env(:giraff, Giraff.Application)[:env]
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

  defp get_opened_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, {_, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end

  @impl true
  def remote_boot(%DockerBackend{parent_ref: parent_ref} = state) do
    if state.on_new_boot, do: state.on_new_boot.(%{name: state.name})

    {resp, req_connect_time} =
      with_elapsed_ms(fn ->
        env = state.env |> Map.to_list() |> Enum.map(fn {x, y} -> "#{x}=#{y}" end)

        port = get_opened_port()
        web_port = get_opened_port()

        env = [
          "OPENED_PORT=#{port}",
          "INTERNAL_OPENED_PORT=#{port}",
          "PRIVATE_IP=#{state.local_ip}",
          "PORT=#{web_port}"
          | env
        ]

        # http_post!("#{state.host}/v1.43/images/create?fromImage=#{state.image}",
        body =
          http_post!("#{state.host}/v1.47/containers/create",
            content_type: "application/json",
            headers: [
              {"Content-Type", "application/json"}
            ],
            connect_timeout: state.boot_timeout,
            body:
              Jason.encode!(%{
                Entrypoint: ["function"],
                Hostname: state.livename,
                Domainname: state.livename,
                Image: state.image,
                Env: env,
                HostConfig: %{
                  NetworkMode: "host",
                  Memory: state.memory_mb * 1024 * 1024,
                  NanoCPUs: state.millicpu * 1_000_000,
                  Binds: [
                    "/var/run/docker.sock:/var/run/docker.sock"
                  ]
                }
              })
          )

        container_id = Map.fetch!(Jason.decode!(body), "Id")

        Logger.debug("Created container #{container_id}")

        http_post!("#{state.host}/v1.47/containers/#{container_id}/start",
          connect_timeout: state.boot_timeout,
          content_type: "text/plain",
          headers: [
            {"Content-Type", "text/plain"}
          ],
          body: ""
        )

        if state.on_accepted_offer,
          do:
            state.on_accepted_offer.(%{
              name: state.name,
              price: Application.fetch_env!(:giraff, :cost_per_request)
            })

        {:success, container_id, "127.0.0.1"}
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

        new_state = %DockerBackend{
          new_state
          | remote_terminator_pid: remote_terminator_pid,
            runner_node_name: node(remote_terminator_pid)
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

    headers = Keyword.fetch!(opts, :headers)
    body = Keyword.fetch!(opts, :body)
    connect_timeout = Keyword.fetch!(opts, :connect_timeout)
    content_type = Keyword.fetch!(opts, :content_type)

    headers = [{"Content-Type", content_type} | headers]

    case HTTPoison.post(url, body, headers, recv_timeout: connect_timeout) do
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}}
      when status in 200..299 ->
        response_body

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        raise "failed POST #{url} with #{inspect(status)}: #{inspect(resp_body)} #{inspect(headers)} with body #{inspect(body)}"

      {:error, %HTTPoison.Error{reason: reason}} ->
        raise "failed POST #{url} with #{inspect(reason)} #{inspect(headers)}"
    end
  end
end
