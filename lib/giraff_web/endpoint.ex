defmodule GiraffWeb.Endpoint do
  use Plug.Router

  require Logger

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

  defp after_speech_recognition(transcription) do
    sentiment =
      FLAME.call(Giraff.SentimentBackend, fn ->
        sentiment = AI.SentimentRecognition.analyze_text(transcription)
        Logger.info("Sentiment: #{inspect(sentiment)}")
        sentiment
      end)

    FLAME.cast(
      Giraff.EndGameBackend,
      fn ->
        Logger.info("End game with #{transcription}")
      end,
      link: false
    )

    sentiment
  end

  defp process_speech(conn, audio_data) do
    with {:ok, transcription, sentiment} <-
           FLAME.call(
             Giraff.SpeechToTextBackend,
             fn ->
               with {:ok, transcription} <- AI.SpeechRecognition.transcribe_audio(audio_data),
                    {:ok, sentiment} <- after_speech_recognition(transcription) do
                 {:ok, transcription, sentiment}
               else
                 {:error, reason} ->
                   Logger.error("Speech recognition failed: #{inspect(reason)}")
                   {:error, :speech_recognition_failed}
               end
             end
           ) do
      case sentiment do
        %{label: "POS"} ->
          FLAME.cast(
            Giraff.TextToSpeechBackend,
            fn ->
              {:ok, file_path} = AI.TextToSpeech.speak(transcription)
              audio_blob = File.read!(file_path)

              FLAME.cast(
                Giraff.EndGameBackend,
                fn ->
                  Logger.info("End game")

                  temp_file =
                    Path.join(
                      System.tmp_dir(),
                      "end_game_speech_#{:erlang.unique_integer([:positive])}.wav"
                    )

                  File.write!(temp_file, audio_blob)
                  File.rm!(temp_file)
                  :ok
                end,
                link: false
              )

              File.rm!(file_path)
            end,
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
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(422, Jason.encode!(%{error: "Transcription failed: #{reason}"}))
    end
  end

  post "/" do
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

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(%{error: "Missing audio file"}))
        end
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
