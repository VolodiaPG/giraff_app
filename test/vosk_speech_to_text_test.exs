defmodule VoskSpeechToTextTest do
  use ExUnit.Case
  doctest FLAMERetry

  require Logger

  setup_all do
    pid =
      start_supervised!(
        {FLAME.Pool,
         name: Giraff.VoskSpeechToTextBackend,
         backend: FLAME.LocalBackend,
         min: 0,
         max: 1,
         max_concurrency: 10}
      )

    path = Path.join([System.get_env("PATH_AUDIO"), "8842-304647-0007.wav"])
    data = File.read!(path)

    %{pool: pid, data: data}
  end

  test "vosk speech to text with AI.Vosk", %{data: data} do
    result = Giraff.VoskSpeechToText.speech_to_text(data)
    assert {:ok, "that's wonderful"} = result
  end

  test "vosk speech to text with AI.Vosk, with callback", %{data: data} do
    parent = self()

    result =
      Giraff.VoskSpeechToText.speech_to_text(data, fn transcription ->
        send(parent, transcription)
      end)

    assert {:ok, "that's wonderful"} = result
    assert_receive {:ok, "that's wonderful"}
  end

  test "vosk speech to text with local backend", %{data: data} do
    result =
      apply(
        FLAME.Pool,
        :call,
        Giraff.VoskSpeechToText.remote_speech_to_text_spec(data, [])
      )

    assert {:ok, "that's wonderful"} = result
  end

  test "vosk speech to text with local backend, after callback", %{data: data} do
    parent = self()

    result =
      apply(
        FLAME.Pool,
        :call,
        Giraff.VoskSpeechToText.remote_speech_to_text_spec(data,
          after_callback: fn transcription ->
            send(parent, transcription)
          end
        )
      )

    assert {:ok, "that's wonderful"} = result
    assert_receive {:ok, "that's wonderful"}
  end
end
