defmodule Giraff.AI.SpeechRecognition do
  require Logger

  def setup_whisper do
    with {:ok, model_info} <- Bumblebee.load_model({:hf, "openai/whisper-tiny"}),
         {:ok, featurizer} <- Bumblebee.load_featurizer({:hf, "openai/whisper-tiny"}),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer({:hf, "openai/whisper-tiny"}),
         {:ok, serving} <-
           Bumblebee.Audio.speech_to_text(model_info, featurizer, tokenizer,
             max_new_tokens: 100,
             chunk_length: 30_000,
             stride_length: 1000,
             language: "english"
           ) do
      {:ok, serving}
    else
      error ->
        Logger.error("Failed to setup Whisper: #{inspect(error)}")
        {:error, :setup_failed}
    end
  end

  def transcribe_audio(serving, audio_path) do
    serving = Giraff.AI.SpeechRecognitionServer.get_serving()

    case Nx.Serving.run(serving, audio_path) do
      {:ok, result} ->
        {:ok, result.text}

      error ->
        Logger.error("Failed to transcribe audio: #{inspect(error)}")
        {:error, :transcription_failed}
    end
  end
end
