defmodule GiraffWeb.Endpoint do
  use Plug.Router

  require Logger

  plug(:match)
  plug(:dispatch)

  # Use forward or scope for path grouping
  forward("/api", to: GiraffWeb.Router)

  get "/health" do
    send_resp(conn, 200, "")
  end

  post "/" do
    {:ok, res} =
      FLAME.call(Giraff.FFMpegRunner, fn ->
        {res, 0} = System.cmd("uname", ["-a"])
        {:ok, res}
      end)

    {:ok, lsres} =
      FLAME.call(Giraff.TotoRunner, fn ->
        {res, 0} = System.cmd("ls", [])
        {:ok, res}
      end)

    tosend = Jason.encode!(%{"uname" => res, "ls" => lsres})

    Logger.debug("Got #{tosend}")

    conn |> send_resp(200, tosend)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
