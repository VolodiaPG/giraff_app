defmodule GiraffWeb.Endpoint do
  use Plug.Router

  require Logger

  plug(:match)
  plug(:dispatch)

  get "/health" do
    send_resp(conn, 200, "")
  end

  post "/" do
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
