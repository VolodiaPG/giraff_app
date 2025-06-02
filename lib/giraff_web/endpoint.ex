defmodule GiraffWeb.Endpoint do
  use Plug.Router

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

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

  defp process_speech(conn, audio_data) do
    Giraff.Cost.on_new_request_start({:global, :cost_server})

    case Giraff.Endpoint.endpoint(audio_data) do
      {:ok, result} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          Jason.encode!(result)
        )

      {:error, {code, reason}} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            error_code: code,
            reason: reason
          })
        )

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          500,
          Jason.encode!(%{
            reason: reason
          })
        )
    end
  after
    Giraff.Cost.on_new_request_end({:global, :cost_server})
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
