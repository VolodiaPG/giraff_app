defmodule GiraffWeb.Endpoint do
  use Plug.Router

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias FLAMETracing, as: FLAMEAlias

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason,
    # Increase max file size to 100MB
    length: 100_000_000
  )

  plug(:match)
  plug(:dispatch)

  get "/health" do
    send_resp(conn, 200, "")
  end

  defp analyze_sentiment(caller, transcription) do
    # Tracer.with_span "analyze_sentiment" do
    sentiment = AI.SentimentRecognition.analyze_text(transcription)
    Logger.debug("Sentiment: #{inspect(sentiment)}")
    Tracer.add_event("sentiment_analyzed", %{sentiment: inspect(sentiment)})
    Tracer.set_attribute("transcription", transcription)
    Tracer.set_attribute("sentiment", inspect(sentiment))

    send(caller, {caller, transcription, sentiment})
    :ok
    # end
  end

  defp handle_end_game(transcription) do
    # Tracer.with_span "handle_end_game" do
    Logger.debug("End game with #{transcription}")
    Tracer.add_event("game_ended", %{transcription: transcription})
    Tracer.set_attribute("transcription", transcription)
    # end
  end

  defp speech_recognition(audio_data) do
    # Tracer.with_span "speech_recognition (inference)" do
    AI.SpeechRecognition.transcribe_audio(audio_data)
    # end
  end

  defp perform_speech_to_text(caller, audio_data) do
    # Tracer.with_span "speech_to_text" do
    with {:ok, transcription} <- speech_recognition(audio_data) do
      Logger.debug("Got transcription #{inspect(transcription)}")
      after_speech_recognition(caller, transcription)
      :ok
    else
      {:error, reason} ->
        Tracer.add_event("speech_recognition.error", %{reason: reason})
        Logger.error("Speech recognition failed: #{inspect(reason)}")
        Tracer.add_event("speech_recognition_failed", %{error: inspect(reason)})
        {:error, :speech_recognition_failed}
    end

    # end
  end

  defp handle_text_to_speech(caller, transcription) do
    # Tracer.with_span "text_to_speech" do
    {:ok, file_path} = AI.TextToSpeech.speak(transcription)
    audio_blob = File.read!(file_path)
    Tracer.set_attribute("transcription", transcription)
    Tracer.set_attribute("file_path", file_path)

    FLAMEAlias.cast(
      Giraff.EndGameBackend,
      fn -> handle_end_game_speech(audio_blob) end,
      caller_pid: caller
    )

    File.rm!(file_path)
    # end
  end

  defp handle_end_game_speech(audio_blob) do
    # Tracer.with_span "handle_end_game_speech" do
    Logger.info("End game")
    Tracer.add_event("end_game_speech_started", %{})

    temp_file =
      Path.join(
        System.tmp_dir(),
        "end_game_speech_#{:erlang.unique_integer([:positive])}.wav"
      )

    File.write!(temp_file, audio_blob)
    Tracer.set_attribute("temp_file", temp_file)
    File.rm!(temp_file)
    :ok
    # end
  end

  defp after_speech_recognition(caller, transcription) do
    # Tracer.with_span "after_speech_recognition" do
    FLAMEAlias.cast(
      Giraff.SentimentBackend,
      fn ->
        analyze_sentiment(caller, transcription)

        FLAMEAlias.cast(
          Giraff.EndGameBackend,
          fn -> handle_end_game(transcription) end,
          caller_pid: caller
        )
      end,
      caller_pid: caller,
      retries: 2,
      fallback_function: fn ->
        # Tracer.with_span "after_speech_recognition.degraded" do
        Tracer.add_event("after_speech_recognition failed, using degraded result",
          transcription: transcription
        )

        FLAMEAlias.cast(
          Giraff.EndGameBackend,
          fn -> handle_end_game(transcription) end
        )

        send(caller, {caller, transcription, %{label: "NEG"}})
        :ok
        # end
      end
    )

    # end
  end

  defp degraded_speech_recognition(caller, audio_data) do
    # Tracer.with_span "speech_recognition.degraded" do
    Logger.warning("Speech recognition could not be called, using degraded function")
    Tracer.add_event("using_degraded_speech_recognition", %{})

    with {:ok, res} <- AI.Vosk.call(audio_data),
         json_res <- Jason.decode!(res),
         %{"text" => transcription} <- json_res do
      after_speech_recognition(caller, transcription)
    else
      {:error, reason} ->
        Tracer.add_event("degraded_speech_recognition.error", reason: reason)
        Tracer.set_status(OpenTelemetry.status(:error, "Speech recognition failed"))
        {:error, :speech_recognition_failed}
    end

    # end
  end

  defp await_end_process_speech(conn, caller) do
    receive do
      {^caller, transcription, sentiment} ->
        Logger.debug("Got transcription and sentiment: #{transcription}, #{inspect(sentiment)}")

        case sentiment do
          %{label: "POS"} ->
            FLAMEAlias.cast(
              Giraff.TextToSpeechBackend,
              fn -> handle_text_to_speech(caller, transcription) end,
              retries: 10,
              base_delay: 1000,
              exponential_factor: 2,
              caller_pid: caller,
              fallback_function: fn ->
                Tracer.set_status(OpenTelemetry.status(:error, "Text to speech failed"))
              end
            )

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              200,
              Jason.encode!(%{
                transcription: transcription,
                sentiment: "Sentiment is positive"
              })
            )

          _ ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{transcription: transcription}))
        end

      {:EXIT, _from, :normal} ->
        await_end_process_speech(conn, caller)

      {:EXIT, _from, reason} ->
        Tracer.set_status(
          OpenTelemetry.status(:error, "Process exited with reason: #{inspect(reason)}")
        )
    after
      120_000 ->
        Logger.error("Timeout waiting for transcription and sentiment")

        Tracer.set_status(
          OpenTelemetry.status(:error, "Timeout waiting for transcription and setntiment")
        )

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(422, Jason.encode!(%{error: "Timeout waiting for
              transcription and sentiment"}))
    end
  end

  defp process_speech(conn, audio_data) do
    # Tracer.with_span "process_speech" do
    caller = self()

    with :ok <-
           FLAMEAlias.cast(
             Giraff.SpeechToTextBackend,
             fn ->
               perform_speech_to_text(caller, audio_data)
             end,
             retries: 1,
             caller_pid: caller,
             fallback_function: fn ->
               FLAMEAlias.cast(
                 Giraff.VoskSpeechToTextBackend,
                 fn ->
                   degraded_speech_recognition(caller, audio_data)
                 end,
                 caller_pid: caller,
                 retries: 3,
                 base_delay: 1000
               )
             end
           ) do
      await_end_process_speech(conn, caller)
    else
      {:error, reason} ->
        Tracer.set_status(OpenTelemetry.status(:error, "Process speech error:
              #{inspect(reason)}"))

        Logger.error("Process speech error: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(422, Jason.encode!(%{error: "Transcription failed: #{reason}"}))
    end

    # end
  end

  post "/" do
    Tracer.with_span "start_processing_requests" do
      Logger.metadata(span_ctx: Tracer.current_span_ctx())

      try do
        case get_req_header(conn, "content-type") do
          ["audio/" <> _] ->
            # Handle raw audio file upload
            {:ok, body, _conn} = read_body(conn)
            process_speech(conn, body)

          _ ->
            # Handle multipart form uploads
            case conn.body_params do
              %{"file" => %Plug.Upload{path: path}} ->
                data = File.read!(path)
                process_speech(conn, data)

              params ->
                Logger.warning("Invalid params received: #{inspect(params)}")
                Tracer.add_event("invalid_params_received", %{params: inspect(params)})

                event =
                  OpenTelemetry.event("process_post_request_on_invalid_params",
                    params: inspect(params)
                  )

                Tracer.add_events([event])

                Tracer.set_attribute("params", inspect(params))

                conn
                |> put_resp_content_type("application/json")
                |> send_resp(400, Jason.encode!(%{error: "Missing audio file"}))
            end
        end
      rescue
        e ->
          Tracer.record_exception(e, __STACKTRACE__)

          Tracer.set_status(
            OpenTelemetry.status(:error, "Request processing error: #{inspect(e)}")
          )

          Logger.debug("Request processing error: #{inspect(e)}")

          reraise(e, __STACKTRACE__)
      end
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
