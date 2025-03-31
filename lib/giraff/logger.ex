defmodule Giraff.Logger.OpenTelemetryBackend do
  @behaviour :gen_event

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def init(__MODULE__) do
    {:ok, %{}}
  end

  @impl true
  def init(config) do
    {:ok, config}
  end

  @impl true
  def handle_event({level, _gl, {Logger, msg, timestamp, metadata}}, state) do
    severity = level_to_severity(level)

    # span_ctx = Tracer.current_span_ctx()
    span_ctx = metadata[:span_ctx]
    Tracer.set_current_span(span_ctx)

    if not is_nil(span_ctx) do
      attributes = %{
        "log.severity" => Atom.to_string(level),
        "log.message" => IO.iodata_to_binary(msg)
      }

      attributes = add_metadata_attributes(attributes, metadata)

      Tracer.add_event("log", attributes)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:configure, new_config}, state) do
    {:ok, :ok, Map.merge(state, new_config)}
  end

  # Convertir les niveaux de log Elixir en niveaux de sévérité OpenTelemetry
  defp level_to_severity(:debug), do: :DEBUG
  defp level_to_severity(:info), do: :INFO
  defp level_to_severity(:notice), do: :INFO
  defp level_to_severity(:warning), do: :WARN
  defp level_to_severity(:warn), do: :WARN
  defp level_to_severity(:error), do: :ERROR
  defp level_to_severity(:critical), do: :ERROR
  defp level_to_severity(:alert), do: :ERROR
  defp level_to_severity(:emergency), do: :ERROR
  defp level_to_severity(_), do: :INFO

  defp add_metadata_attributes(attributes, metadata) do
    metadata
    |> Enum.reduce(attributes, fn
      {:pid, value}, acc ->
        Map.put(acc, "process.pid", inspect(value))

      {:module, value}, acc ->
        Map.put(acc, "code.namespace", inspect(value))

      {:function, value}, acc ->
        Map.put(acc, "code.function", inspect(value))

      {:file, value}, acc ->
        Map.put(acc, "code.filepath", value)

      {:line, value}, acc ->
        Map.put(acc, "code.lineno", value)

      {key, value}, acc
      when is_atom(key) and (is_binary(value) or is_number(value) or is_atom(value)) ->
        Map.put(acc, Atom.to_string(key), value)

      _, acc ->
        acc
    end)
  end
end
