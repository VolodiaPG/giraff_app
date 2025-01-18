defmodule Giraff.AI.SpeechRecognition do
  require Logger

  def setup_whisper do
    with {:ok, model_info} <- Bumblebee.load_model({:hf, "openai/whisper-tiny.en"}),
         {:ok, featurizer} <- Bumblebee.load_featurizer({:hf, "openai/whisper-tiny.en"}),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer({:hf, "openai/whisper-tiny.en"}),
         {:ok, generation_config} =
           Bumblebee.load_generation_config({:hf, "openai/whisper-tiny.en"}),
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
    serving = Giraff.AI.SpeechRecognitionServer.get_serving()

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
