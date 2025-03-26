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

  defp analyze_sentiment(transcription) do
    Tracer.with_span "analyze_sentiment" do
      sentiment = AI.SentimentRecognition.analyze_text(transcription)
      Logger.info("Sentiment: #{inspect(sentiment)}")
      Tracer.add_event("sentiment_analyzed", %{sentiment: inspect(sentiment)})
      Tracer.set_attribute("transcription", transcription)
      Tracer.set_attribute("sentiment", inspect(sentiment))
      sentiment
    end
  end

  defp handle_end_game(transcription) do
    Tracer.with_span "handle_end_game" do
      Logger.info("End game with #{transcription}")
      Tracer.add_event("game_ended", %{transcription: transcription})
      Tracer.set_attribute("transcription", transcription)
    end
  end

  defp speech_recognition(audio_data) do
    Tracer.with_span "speech_recognition (inference)" do
      AI.SpeechRecognition.transcribe_audio(audio_data)
    end
  end

  defp perform_speech_to_text(audio_data) do
    Tracer.with_span "speech_recognition" do
      with {:ok, transcription} <- speech_recognition(audio_data),
           {:ok, sentiment} <-
             after_speech_recognition(transcription) do
        Tracer.set_attribute("transcription", transcription)
        Tracer.set_attribute("sentiment", sentiment)
        {:ok, transcription, sentiment}
      else
        {:error, reason} ->
          Tracer.add_event("speech_recognition.error", %{reason: reason})
          Logger.error("Speech recognition failed: #{inspect(reason)}")
          Tracer.add_event("speech_recognition_failed", %{error: inspect(reason)})
          {:error, :speech_recognition_failed}
      end
    end
  end

  defp handle_text_to_speech(transcription) do
    Tracer.with_span "text_to_speech" do
      {:ok, file_path} = AI.TextToSpeech.speak(transcription)
      audio_blob = File.read!(file_path)
      Tracer.set_attribute("transcription", transcription)
      Tracer.set_attribute("file_path", file_path)

      FLAMEAlias.cast(
        Giraff.EndGameBackend,
        fn -> handle_end_game_speech(audio_blob) end
      )

      File.rm!(file_path)
    end
  end

  defp handle_end_game_speech(audio_blob) do
    Tracer.with_span "handle_end_game_speech" do
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
    end
  end

  defp after_speech_recognition(transcription) do
    Tracer.with_span "after_speech_recognition" do
      sentiment =
        FLAMEAlias.call(
          Giraff.SentimentBackend,
          fn ->
            analyze_sentiment(transcription)
          end,
          retries: 1,
          fallback_function: fn ->
            Tracer.add_event("after_speech_recognition failed, using degraded result",
              transcription: transcription
            )

            {:ok, %{label: "NEG"}}
          end
        )

      FLAMEAlias.cast(
        Giraff.EndGameBackend,
        fn -> handle_end_game(transcription) end
      )

      Tracer.set_attribute("transcription", transcription)
      Tracer.set_attribute("sentiment", inspect(sentiment))

      sentiment
    end
  end

  defp degraded_speech_recognition(audio_data) do
    Tracer.with_span "degraded_speech_recognition" do
      Logger.warning("Speech recognition could not be called, using degraded function")
      Tracer.add_event("using_degraded_speech_recognition", %{})

      with {:ok, res} <- AI.Vosk.call(audio_data),
           json_res <- Jason.decode!(res),
           %{"text" => transcription} <- json_res,
           {:ok, sentiment} <-
             after_speech_recognition(transcription) do
        Tracer.add_event("degraded_speech_recognition",
          transcription: transcription,
          sentiment: inspect(sentiment)
        )

        {:ok, transcription, sentiment}
      else
        {:error, reason} ->
          Tracer.add_event("degraded_speech_recognition.error", reason: reason)
          Tracer.set_status(OpenTelemetry.status(:error, "Speech recognition failed"))
          {:error, :speech_recognition_failed}
      end
    end
  end

  defp process_speech(conn, audio_data) do
    Tracer.with_span "process_speech" do
      with {:ok, transcription, sentiment} <-
             FLAMEAlias.call(
               Giraff.SpeechToTextBackend,
               fn -> perform_speech_to_text(audio_data) end,
               retries: 1,
               fallback_function: fn ->
                 FLAMEAlias.call(
                   Giraff.VoskSpeechToTextBackend,
                   fn ->
                     degraded_speech_recognition(audio_data)
                   end,
                   retries: 3,
                   base_delay: 1000
                 )
               end
             ) do
        Tracer.add_event("Got transcription and sentiment",
          transcription: transcription,
          sentiment: inspect(sentiment)
        )

        case sentiment do
          %{label: "POS"} ->
            FLAMEAlias.cast(
              Giraff.TextToSpeechBackend,
              fn -> handle_text_to_speech(transcription) end,
              retries: 10,
              base_delay: 1000,
              exponential_factor: 2,
              fallback_function: fn ->
                Tracer.set_status(OpenTelemetry.status(:error, "Text to speech failed"))
              end
            )

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              200,
              Jason.encode!(%{transcription: transcription, sentiment: "Sentiment is positive"})
            )

          _ ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{transcription: transcription}))
        end
      else
        {:error, reason} ->
          Tracer.add_event("process_speech.error", reason: reason)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(422, Jason.encode!(%{error: "Transcription failed: #{reason}"}))
      end
    end
  end

  post "/" do
    # traceparent = get_req_header(conn, "traceparent") |> List.first()
    # tracestate = get_req_header(conn, "tracestate") |> List.first()

    # Logger.info("Traceparent: #{inspect(traceparent)}, Tracestate: #{inspect(tracestate)}")

    # Tracer.with_span "process post request on /" do

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
        Tracer.record_exception(e)

        Tracer.set_status(OpenTelemetry.status(:error, "Request processing error: #{inspect(e)}"))

        raise e
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
