defmodule SpeechToTextTest do
  use ExUnit.Case
  doctest FLAMERetry

  require Logger

  setup_all do
    pid =
      start_supervised!(
        {FLAME.Pool,
         name: Giraff.SpeechToTextBackend,
         backend: FLAME.LocalBackend,
         min: 0,
         max: 1,
         max_concurrency: 10}
      )

    path = Path.join([System.get_env("PATH_AUDIO"), "8842-304647-0007.wav"])
    data = File.read!(path)

    %{pool: pid, data: data}
  end

  test "nominal", %{data: data} do
    transcription = Giraff.SpeechToText.speech_to_text(data)
    assert {:ok, " I'm going to be the most wonderful."} == transcription
  end

  test "nominal, callback", %{data: data} do
    caller = self()

    transcription =
      Giraff.SpeechToText.speech_to_text(data, fn transcription ->
        send(
          caller,
          transcription
        )
      end)

    assert {:ok, " I'm going to be the most wonderful."} == transcription
    assert_receive {:ok, " I'm going to be the most wonderful."}
  end

  test "nominal with local backend", %{data: data} do
    transcription =
      apply(FLAME.Pool, :call, Giraff.SpeechToText.remote_speech_to_text_spec(data, []))

    assert {:ok, " I'm going to be the most wonderful."} == transcription
  end

  test "nominal with local backend, with callback", %{data: data} do
    caller = self()

    transcription =
      apply(
        FLAME.Pool,
        :call,
        Giraff.SpeechToText.remote_speech_to_text_spec(data,
          after_callback: fn transcription ->
            send(
              caller,
              transcription
            )
          end
        )
      )

    assert {:ok, " I'm going to be the most wonderful."} == transcription
    assert_receive {:ok, " I'm going to be the most wonderful."}
  end
end
