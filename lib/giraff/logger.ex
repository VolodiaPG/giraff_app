defmodule Giraff.Logger.OpenTelemetryBackend do
  @moduledoc """
  Un backend de journalisation qui exporte les logs vers OpenTelemetry.
  
  Ce backend capture les messages de log et les convertit en événements OpenTelemetry,
  permettant ainsi d'intégrer les logs dans le système de traçage.
  """
  @behaviour :gen_event

  require Logger
  alias OpenTelemetry.Ctx
  alias OpenTelemetry.Tracer

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
    # Convertir le niveau de log en attribut OpenTelemetry
    severity = level_to_severity(level)
    
    # Récupérer le contexte de span actuel
    span_ctx = Tracer.current_span_ctx()
    
    if span_ctx != :undefined do
      # Ajouter l'événement de log à la span actuelle
      attributes = %{
        "log.severity" => Atom.to_string(level),
        "log.message" => IO.iodata_to_binary(msg)
      }
      
      # Ajouter les métadonnées pertinentes comme attributs
      attributes = add_metadata_attributes(attributes, metadata)
      
      # Ajouter l'événement à la span
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

  # Ajouter les métadonnées pertinentes comme attributs
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
      
      {key, value}, acc when is_atom(key) and (is_binary(value) or is_number(value) or is_atom(value)) ->
        Map.put(acc, Atom.to_string(key), value)
      
      _, acc ->
        acc
    end)
  end
end

defmodule Giraff.Logger do
  @moduledoc """
  Module de configuration pour l'intégration des logs avec OpenTelemetry.
  """
  
  @doc """
  Configure le backend de journalisation OpenTelemetry.
  
  ## Exemples
  
      # Dans votre fichier de configuration (config/config.exs)
      config :logger,
        backends: [:console, Giraff.Logger.OpenTelemetryBackend]
  
      # Dans votre application
      Giraff.Logger.setup()
  """
  def setup do
    # Vérifier si le backend est déjà configuré
    backends = Application.get_env(:logger, :backends, [])
    
    unless Enum.member?(backends, Giraff.Logger.OpenTelemetryBackend) do
      # Ajouter le backend OpenTelemetry aux backends existants
      new_backends = backends ++ [Giraff.Logger.OpenTelemetryBackend]
      Application.put_env(:logger, :backends, new_backends)
      
      # Recharger la configuration du Logger
      Logger.configure(backends: new_backends)
    end
    
    :ok
  end
end
