defmodule Giraff.SpeechToText do
  @moduledoc """
  Speech to text module to be used by the Giraff app
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def speech_to_text(audio, after_callback \\ nil) when is_binary(audio) do
    with transcription = {:ok, text} <- AI.SpeechRecognition.transcribe_audio(audio) do
      Logger.debug("Got transcription #{inspect(text)}")
      if after_callback, do: after_callback.(transcription)
      transcription
    else
      {:error, reason} ->
        Tracer.add_event("speech_recognition.error", %{reason: reason})
        Logger.error("Speech recognition failed: #{inspect(reason)}")
        Tracer.add_event("speech_recognition_failed", %{error: inspect(reason)})
        {:error, {:speech_recognition_failed, reason}}
    end
  end

  @doc """
  Outputs the settings to call the function on the appropriate FLAME backend
  """
  def remote_speech_to_text_spec(audio, opts) when is_binary(audio) do
    Keyword.put_new(opts, :retries, 1)

    [
      Giraff.SpeechToTextBackend,
      fn -> __MODULE__.speech_to_text(audio, Keyword.get(opts, :after_callback)) end,
      opts
    ]
  end
end
