defmodule AI.TextToSpeech do
  require Logger

  def speak(text) do
    Logger.debug("Speaking: #{text}")
    temp_file = Path.join(System.tmp_dir(), "speech_#{:erlang.unique_integer([:positive])}.wav")
    System.cmd("mimic", ["-t", text, "-o", temp_file])
    {:ok, temp_file}
  end
end
