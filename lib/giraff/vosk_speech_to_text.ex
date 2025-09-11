defmodule Giraff.VoskSpeechToText do
  @moduledoc """
  Vosk speech to text module to be used as a fallback by the Giraff app
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def speech_to_text(audio, after_callback \\ nil) when is_binary(audio) do
    Logger.info("Using Vosk for speech recognition")
    Tracer.add_event("using_vosk_speech_recognition", %{})

    with {:ok, res} <- AI.Vosk.call(audio),
         json_res <- Jason.decode!(res),
         %{"text" => transcription} <- json_res do
      Logger.debug("Got Vosk transcription: #{inspect(transcription)}")

      res =
        {:ok, transcription}

      if after_callback do
        after_callback.(res)
      else
        res
      end
    else
      {:error, reason} ->
        Logger.error("Vosk speech recognition failed: #{inspect(reason)}")
        Tracer.add_event("vosk_speech_recognition_failed", %{error: inspect(reason)})
        {:error, {:vosk_speech_recognition_failed, reason}}
    end
  end

  @doc """
  Outputs the settings to call the function on the appropriate FLAME backend
  """
  def remote_speech_to_text_spec(audio, opts) when is_binary(audio) do
    opts = Keyword.put_new(opts, :retries, 3)
    opts = Keyword.put_new(opts, :base_delay, 2000)

    [
      Giraff.VoskSpeechToTextBackend,
      fn -> __MODULE__.speech_to_text(audio, Keyword.get(opts, :after_callback)) end,
      opts
    ]
  end
end
