defmodule Giraff.Endpoint do
  @moduledoc """
    A wrapper for the important parts of the endpoint, so it is easier to test
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @flame FLAMERetry

  def endpoint(audio_data) do
    parent = self()

    with {:ok, pid} <-
           apply(
             @flame,
             :cast,
             Giraff.SpeechToText.remote_speech_to_text_spec(audio_data,
               after_callback: fn {:ok, transcription} ->
                 apply(
                   @flame,
                   :cast,
                   sentiment_analysis(parent, transcription)
                 )
               end,
               caller_pid: parent,
               fallback_function: fn ->
                 apply(
                   @flame,
                   :cast,
                   Giraff.VoskSpeechToText.remote_speech_to_text_spec(audio_data,
                     caller_pid: parent,
                     after_callback: fn {:ok, transcription} ->
                       apply(
                         @flame,
                         :cast,
                         sentiment_analysis(parent, transcription)
                       )
                     end
                   )
                 )
               end
             )
           ) do
      await_end_process_speech(parent, pid)
    else
      error = {:error, reason} ->
        Tracer.set_status(OpenTelemetry.status(:error, "Process speech error:
              #{inspect(reason)}"))

        Logger.error("Process speech error: #{inspect(reason)}")
        error
    end
  end

  defp await_end_process_speech(caller, pid) do
    ref = Process.monitor(pid)

    receive do
      {^caller, transcription, sentiment} ->
        Process.demonitor(ref, [:flush])
        Logger.debug("Got transcription and sentiment: #{transcription}, #{inspect(sentiment)}")

        apply(
          @flame,
          :cast,
          Giraff.EndGame.remote_handle_end_game_spec(transcription, caller_pid: caller)
        )

        case sentiment do
          %{label: "POS"} ->
            apply(
              @flame,
              :cast,
              Giraff.TextToSpeech.remote_text_to_speech_spec(transcription,
                caller_pid: caller
              )
            )

            {:ok, %{transcription: transcription, sentiment: "Sentiment is positive"}}

          _ ->
            {:ok, %{transcription: transcription}}
        end

      {:DOWN, ^ref, :process, ^pid, reason} when reason != :normal ->
        Process.demonitor(ref, [:flush])
        {:error, {:process_exited, reason}}

      {:ok_finished_spawned_pid, ^pid, new_pid} ->
        Process.demonitor(ref, [:flush])
        await_end_process_speech(caller, new_pid)
    after
      300_000 ->
        Logger.error("Timeout waiting for transcription and sentiment")

        Tracer.set_status(
          OpenTelemetry.status(:error, "Timeout waiting for transcription and sentiment")
        )

        {:error, {:timeout, "Timeout waiting for
              transcription and sentiment"}}
    end
  end

  defp sentiment_analysis(parent, transcription) do
    Giraff.SentimentAnalysis.remote_analyze_sentiment_spec(transcription,
      after_callback: fn {:ok, sentiment} ->
        send(
          parent,
          {parent, transcription, sentiment}
        )
      end,
      caller_pid: parent,
      fallback_function: fn ->
        {:ok, sentiment} =
          Giraff.SentimentAnalysis.degraded_sentiment_analysis(transcription)

        send(parent, {parent, transcription, sentiment})
      end
    )
  end
end
