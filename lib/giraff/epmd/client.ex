defmodule Giraff.Epmd.Client do
  @moduledoc """
  Module responsible for impersonating Epmd (thus not starting it)

  It aims to extract the port from the last digits of the node name
  """

  # The distribution protocol version number has been 5 ever since Erlang/OTP R6.
  @version 5

  @minimum_port 1_024
  @maximum_port 65_535

  def available_ports_count do
    @maximum_port - @minimum_port + 1
  end

  defp get_port_by_name(str) do
    :erlang.phash2(str, available_ports_count()) + 1_024
  end

  def name_to_port(name) when is_atom(name) do
    name_to_port(Atom.to_string(name))
  end

  def name_to_port(name) when is_list(name) do
    name_to_port(List.to_string(name))
  end

  @doc """
  Translates node name to port number.
  """
  def name_to_port(name) when is_binary(name) do
    node_name = Regex.replace(~r/@.*$/, name, "")
    port_regex = ~r/^(?<rpc>rpc-)|(?<rem>rem-)|(?<port>(?!0)\d{1,5})$/
    matches = Regex.named_captures(port_regex, node_name)

    case matches do
      %{"rpc" => "rpc-"} ->
        {:ok, 0}

      %{"rem" => "rem-"} ->
        {:ok, 0}

      %{"port" => port} ->
        {:ok, String.to_integer(port)}

      _ ->
        {:ok, get_port_by_name(node_name)}
    end
  end

  def start_link do
    :ignore
  end

  def register_node(name, port, _driver) do
    register_node(name, port)
  end

  def register_node(_name, _port) do
    creation = :rand.uniform(3)
    {:ok, creation}
  end

  # def port_please(name, ip, _timeout) do
  #   port_please(name, ip)
  # end

  def port_please(name, _ip) do
    {:ok, port} = name_to_port(name)
    {:port, port, @version}
  end

  # def port_please(name, {127,0,0,1}) do
  #     Logger.debug("Maching on localhost ip")
  #     {:port, System.get_env("INTERNAL_OPENED_PORT"), @version}
  # end

  def names(_hostname) do
    {:error, "I don't know what other nodes there are."}
  end

  def address_please(_name, host, address_family) do
    :inet.getaddr(host, address_family)
  end

  # def listen_port_please(name, _host) do
  #   # port = name_to_port(name)
  #   port = System.get_env("INTERNAL_OPENED_PORT")
  #   # Logger.debug("listen port: #{port}")
  #  {:ok, port}
  # end
end
