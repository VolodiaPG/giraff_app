defmodule EndGameTest do
  use ExUnit.Case
  doctest FLAMERetry

  require Logger

  setup_all do
    pid =
      start_supervised!(
        {FLAME.Pool,
         name: Giraff.EndGameBackend,
         backend: FLAME.LocalBackend,
         min: 0,
         max: 1,
         max_concurrency: 10}
      )

    %{pool: pid}
  end

  test "handle end game" do
    transcription = "This is the end of the game"
    result = Giraff.EndGame.handle_end_game(transcription)
    assert {:ok, :game_ended} = result
  end

  test "handle end game with local backend" do
    transcription = "This is the end of the game"

    result =
      apply(FLAME.Pool, :call, Giraff.EndGame.remote_handle_end_game_spec(transcription, []))

    assert {:ok, :game_ended} = result
  end

  test "handle end game speech" do
    # Dummy audio data
    audio_blob = <<0, 1, 2, 3, 4, 5>>
    result = Giraff.EndGame.handle_end_game_speech(audio_blob)
    assert {:ok, :end_game_speech_processed} = result
  end

  test "handle end game speech with local backend" do
    # Dummy audio data
    audio_blob = <<0, 1, 2, 3, 4, 5>>

    result =
      apply(FLAME.Pool, :call, Giraff.EndGame.remote_handle_end_game_speech_spec(audio_blob, []))

    assert {:ok, :end_game_speech_processed} = result
  end
end
