defmodule GiraffWeb.Endpoint do
  use Plug.Router

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  require OpenTelemetry.Ctx, as: Ctx

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

  defp analyze_sentiment(transcription, span_ctx, parent_span_context) do
    Ctx.attach(parent_span_context)
    Tracer.set_current_span(span_ctx)

    Tracer.with_span "analyze_sentiment" do
      sentiment = AI.SentimentRecognition.analyze_text(transcription)
      Logger.info("Sentiment: #{inspect(sentiment)}")
      Tracer.set_attribute("transcription", transcription)
      Tracer.set_attribute("sentiment", inspect(sentiment))
      sentiment
    end
  end

  defp handle_end_game(transcription, span_ctx, parent_span_context) do
    Ctx.attach(parent_span_context)
    Tracer.set_current_span(span_ctx)

    Tracer.with_span "handle_end_game" do
      Logger.info("End game with #{transcription}")
      Tracer.set_attribute("transcription", transcription)
    end
  end

  defp speech_recognition(audio_data, span_ctx, parent_span_context) do
    Ctx.attach(parent_span_context)
    Tracer.set_current_span(span_ctx)

    Tracer.with_span "speech_recognition (inference)" do
      AI.SpeechRecognition.transcribe_audio(audio_data)
    end
  end

  defp perform_speech_to_text(audio_data, span_ctx, parent_span_context) do
    Ctx.attach(parent_span_context)
    Tracer.set_current_span(span_ctx)

    Tracer.with_span "speech_recognition" do
      with {:ok, transcription} <- speech_recognition(audio_data, span_ctx, parent_span_context),
           {:ok, sentiment} <-
             after_speech_recognition(transcription, span_ctx, parent_span_context) do
        Tracer.set_attribute("transcription", transcription)
        Tracer.set_attribute("sentiment", sentiment)
        {:ok, transcription, sentiment}
      else
        {:error, reason} ->
          Tracer.add_event("speech_recognition.error", reason: reason)
          Logger.error("Speech recognition failed: #{inspect(reason)}")
          {:error, :speech_recognition_failed}
      end
    end
  end

  defp handle_text_to_speech(transcription, span_ctx, parent_span_context) do
    Ctx.attach(parent_span_context)
    Tracer.set_current_span(span_ctx)

    Tracer.with_span "text_to_speech" do
      {:ok, file_path} = AI.TextToSpeech.speak(transcription)
      audio_blob = File.read!(file_path)
      Tracer.set_attribute("transcription", transcription)
      Tracer.set_attribute("file_path", file_path)

      FLAME.cast(
        Giraff.EndGameBackend,
        fn -> handle_end_game_speech(audio_blob, span_ctx, parent_span_context) end,
        link: false
      )

      File.rm!(file_path)
    end
  end

  defp handle_end_game_speech(audio_blob, span_ctx, parent_span_context) do
    Ctx.attach(parent_span_context)
    Tracer.set_current_span(span_ctx)

    Tracer.with_span "handle_end_game_speech" do
      Logger.info("End game")

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

  defp after_speech_recognition(transcription, span_ctx, parent_span_context) do
    Ctx.attach(parent_span_context)
    Tracer.set_current_span(span_ctx)

    Tracer.with_span "after_speech_recognition" do
      sentiment =
        FLAME.call(Giraff.SentimentBackend, fn ->
          analyze_sentiment(transcription, span_ctx, parent_span_context)
        end)

      FLAME.cast(
        Giraff.EndGameBackend,
        fn -> handle_end_game(transcription, span_ctx, parent_span_context) end,
        link: false
      )

      Tracer.set_attribute("transcription", transcription)
      Tracer.set_attribute("sentiment", inspect(sentiment))
      sentiment
    end
  end

  defp process_speech(conn, audio_data, span_ctx, parent_span_context) do
    Ctx.attach(parent_span_context)
    Tracer.set_current_span(span_ctx)

    Tracer.with_span "process_speech" do
      with {:ok, transcription, sentiment} <-
             FLAME.call(
               Giraff.SpeechToTextBackend,
               fn -> perform_speech_to_text(audio_data, span_ctx, parent_span_context) end
             ) do
        Tracer.set_attribute("transcription", transcription)
        Tracer.set_attribute("sentiment", inspect(sentiment))

        case sentiment do
          %{label: "POS"} ->
            FLAME.cast(
              Giraff.TextToSpeechBackend,
              fn -> handle_text_to_speech(transcription, span_ctx, parent_span_context) end,
              link: false
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
    Tracer.with_span "process post request on /" do
      span_ctx = Tracer.current_span_ctx()
      parent_span_context = Ctx.get_current()

      try do
        case get_req_header(conn, "content-type") do
          ["audio/" <> _] ->
            # Handle raw audio file upload
            {:ok, body, _conn} = read_body(conn)
            process_speech(conn, body, span_ctx, parent_span_context)

          _ ->
            # Handle multipart form uploads
            case conn.body_params do
              %{"file" => %Plug.Upload{path: path}} ->
                data = File.read!(path)
                process_speech(conn, data, span_ctx, parent_span_context)

              params ->
                Logger.warning("Invalid params received: #{inspect(params)}")

                Tracer.add_event("process_post_request_on_invalid_params", %{
                  params: inspect(params)
                })

                Tracer.set_attribute("params", inspect(params))

                conn
                |> put_resp_content_type("application/json")
                |> send_resp(400, Jason.encode!(%{error: "Missing audio file"}))
            end
        end
      rescue
        e ->
          Tracer.add_event("request_processing_error", %{error: inspect(e)})
          Tracer.set_attribute("error", inspect(e))
          raise e
      end
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
