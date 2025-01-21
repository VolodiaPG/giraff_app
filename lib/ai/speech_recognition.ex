defmodule AI.SpeechRecognition do
  require Logger

  def setup_whisper do
    Logger.debug("Using cache: #{Bumblebee.cache_dir()}")

    with {:ok, model_info} <- Bumblebee.load_model({:local, System.get_env("WHISPER_TINY_DIR")}),
         {:ok, featurizer} <-
           Bumblebee.load_featurizer({:local, System.get_env("WHISPER_TINY_DIR")}),
         {:ok, tokenizer} <-
           Bumblebee.load_tokenizer({:local, System.get_env("WHISPER_TINY_DIR")}),
         {:ok, generation_config} =
           Bumblebee.load_generation_config({:local, System.get_env("WHISPER_TINY_DIR")}),
         serving <-
           Bumblebee.Audio.speech_to_text_whisper(
             model_info,
             featurizer,
             tokenizer,
             generation_config,
             task: nil,
             compile: [batch_size: 5],
             defn_options: [compiler: EXLA]
           ) do
      {:ok, serving}
    else
      error ->
        Logger.error("Failed to setup Whisper: #{inspect(error)}")
        {:error, :setup_failed}
    end
  end

  def transcribe_audio(audio_path) do
    serving = AI.SpeechRecognitionServer.get_serving()

    res = Nx.Serving.run(serving, {:file, audio_path})

    case res do
      %{chunks: [%{text: text} | _]} ->
        {:ok, text}

      _ ->
        Logger.error("Unexpected response format: #{inspect(res)}")
        {:error, :invalid_response}
    end
  end
end
