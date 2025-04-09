defmodule Giraff.TextToSpeech do
  @moduledoc """
  Text to speech module to be used by the Giraff app
  """
end

defmodule Giraff.TextToSpeech do
  @moduledoc """
  Text to speech module to be used by the Giraff app
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def text_to_speech(text) when is_binary(text) do
    with {:ok, file_path} <- AI.TextToSpeech.speak(text) do
      Logger.debug("Text to speech generated file: #{file_path}")
      audio_blob = File.read!(file_path)
      Tracer.set_attribute("transcription", text)
      Tracer.set_attribute("file_path", file_path)
      File.rm!(file_path)
      {:ok, audio_blob}
    else
      error ->
        Tracer.add_event("text_to_speech.error", %{reason: error})
        Logger.error("Text to speech failed: #{inspect(error)}")
        Tracer.add_event("text_to_speech_failed", %{error: inspect(error)})
        {:error, {:text_to_speech_failed, error}}
    end
  end

  @doc """
  Outputs the settings to call the function on the appropriate FLAME backend
  """
  def remote_text_to_speech_spec(text, opts) when is_binary(text) do
    opts = Keyword.put_new(opts, :retries, 10)
    opts = Keyword.put_new(opts, :base_delay, 1000)
    opts = Keyword.put_new(opts, :exponential_factor, 2)

    [
      Giraff.TextToSpeechBackend,
      fn -> __MODULE__.text_to_speech(text) end,
      opts
    ]
  end
end
