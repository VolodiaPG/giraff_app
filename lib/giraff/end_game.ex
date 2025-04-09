defmodule Giraff.EndGame do
  @moduledoc """
  End game module to be used by the Giraff app
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def handle_end_game(transcription) when is_binary(transcription) do
    Logger.debug("End game with #{transcription}")
    Tracer.add_event("game_ended", %{transcription: transcription})
    Tracer.set_attribute("transcription", transcription)
    {:ok, :game_ended}
  end

  @doc """
  Outputs the settings to call the function on the appropriate FLAME backend
  """
  def remote_handle_end_game_spec(transcription, opts) when is_binary(transcription) do
    Keyword.put_new(opts, :retries, 1)

    [
      Giraff.EndGameBackend,
      fn -> __MODULE__.handle_end_game(transcription) end,
      opts
    ]
  end

  def handle_end_game_speech(audio_blob) when is_binary(audio_blob) do
    Logger.info("End game speech processing")
    Tracer.add_event("end_game_speech_started", %{})

    temp_file =
      Path.join(
        System.tmp_dir(),
        "end_game_speech_#{:erlang.unique_integer([:positive])}.wav"
      )

    File.write!(temp_file, audio_blob)
    Tracer.set_attribute("temp_file", temp_file)
    File.rm!(temp_file)
    {:ok, :end_game_speech_processed}
  end

  @doc """
  Outputs the settings to call the function on the appropriate FLAME backend
  """
  def remote_handle_end_game_speech_spec(audio_blob, opts) when is_binary(audio_blob) do
    Keyword.put_new(opts, :retries, 1)

    [
      Giraff.EndGameBackend,
      fn -> __MODULE__.handle_end_game_speech(audio_blob) end,
      opts
    ]
  end
end
