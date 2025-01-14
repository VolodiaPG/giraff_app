defmodule GiraffWeb.Router do
  use Plug.Router

  plug(:match)
  plug(:json_header)
  plug(:dispatch)

  # Helper function for JSON content type
  defp json_header(conn, _opts) do
    put_resp_content_type(conn, "application/json")
  end

  get "/toto" do
    {:ok, res} =
      FLAME.call(Giraff.FFMpegRunner, fn ->
        {res, 0} = System.cmd("uname", ["-a"])
        {:ok, res}
      end)

      {:ok, lsres} = FLAME.call(Giraff.FFMpegRunner, fn ->
              {res, 0} = System.cmd("ls", ["-lia"])
              {:ok, res}
            end)

    conn |> send_resp(200, Jason.encode!(%{"uname" => res, "ls" => lsres}))
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
