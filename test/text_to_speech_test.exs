defmodule TextToSpeechTest do
  use ExUnit.Case
  doctest FLAMERetry

  require Logger

  setup_all do
    pid =
      start_supervised!(
        {FLAME.Pool,
         name: Giraff.TextToSpeechBackend,
         backend: FLAME.LocalBackend,
         min: 0,
         max: 1,
         max_concurrency: 10}
      )

    %{pool: pid}
  end

  test "text to speech with AI.TextToSpeech" do
    text = "Hello, this is a test"
    result = Giraff.TextToSpeech.text_to_speech(text)
    assert {:ok, <<82, 73, 70, 70, 164, _::binary>>} = result
  end

  test "text to speech with AI.TextToSpeech, local backend" do
    text = "Hello, this is a test"
    result = apply(FLAME.Pool, :call, Giraff.TextToSpeech.remote_text_to_speech_spec(text, []))
    assert {:ok, <<82, 73, 70, 70, 164, _::binary>>} = result
  end

  test "text to speech with AI.TextToSpeech, local backend, twice" do
    text = "Hello, this is a test"
    result = apply(FLAME.Pool, :call, Giraff.TextToSpeech.remote_text_to_speech_spec(text, []))
    assert {:ok, <<82, 73, 70, 70, 164, _::binary>>} = result
    result = apply(FLAME.Pool, :call, Giraff.TextToSpeech.remote_text_to_speech_spec(text, []))
    assert {:ok, <<82, 73, 70, 70, 164, _::binary>>} = result
  end
end
