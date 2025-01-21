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

  def process_speech(conn, path) do
    case FLAME.call(
           Giraff.FFMpegRunner,
           fn ->
             AI.SpeechRecognition.transcribe_audio(path)
           end
         ) do
      {:ok, transcription} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{transcription: transcription}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(422, Jason.encode!(%{error: "Transcription failed: #{reason}"}))
    end
  end

  post "/" do
    case conn.body_params do
      %{"file" => %Plug.Upload{path: temp_path}} ->
        process_speech(conn, temp_path)

      %Plug.Upload{path: temp_path} ->
        process_speech(conn, temp_path)

      params ->
        Logger.warning("Invalid params received: #{inspect(params)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Missing audio file"}))
    end
  end

  post "/toto" do
    {:ok, res, lsres} =
      FLAME.call(Giraff.FFMpegRunner, fn ->
        {res, 0} = System.cmd("uname", ["-a"])

        :ok =
          FLAME.cast(Giraff.TotoRunner, fn ->
            {resping, 0} = System.cmd("ping", ["1.1.1.1", "-c", "4"])
            Logger.debug("ping: #{resping}")
            :ok
          end)

        {:ok, lsres} =
          FLAME.call(Giraff.TotoRunner, fn ->
            {res, 0} = System.cmd("ls", [])
            {:ok, res}
          end)

        {:ok, res, lsres}
      end)

    tosend = Jason.encode!(%{"uname" => res, "ls" => lsres})

    Logger.debug("Got #{tosend}")

    conn |> send_resp(200, tosend)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
