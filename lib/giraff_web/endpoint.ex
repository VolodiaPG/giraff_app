defmodule GiraffWeb.Endpoint do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  # Use forward or scope for path grouping
  forward("/api", to: GiraffWeb.Router)

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
