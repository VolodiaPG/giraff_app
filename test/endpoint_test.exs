defmodule TestBackend do
  defstruct name: nil,
            min: 0,
            max: 1,
            max_concurrency: 10

  def spec(state) do
    args =
      state
      |> Map.from_struct()
      |> Map.take([
        :name,
        :min,
        :max,
        :max_concurrency
      ])
      |> Keyword.new()

    {FLAME.Pool, [backend: FLAME.LocalBackend] ++ args}
  end
end

defmodule FailTestBackend do
  use ExUnit.Case

  defstruct name: nil,
            min: 0,
            max: 1,
            max_concurrency: 10

  def spec(state) do
    counter =
      start_supervised!(
        {FLAME.FailBackend.Counter, initial_value: 0, name: :"#{state.name}.Counter"},
        id: :"#{state.name}.Counter"
      )

    args =
      state
      |> Map.take([
        :name,
        :min,
        :max,
        :max_concurrency
      ])
      |> Keyword.new()

    {FLAME.Pool, [backend: {FLAME.FailBackend, fail_after_counter: counter}] ++ args}
  end
end

defmodule EndpoindTest do
  use ExUnit.Case
  doctest Giraff.Endpoint

  require Logger

  setup context do
    path = Path.join([System.get_env("PATH_AUDIO"), "8842-304647-0007.wav"])
    data = File.read!(path)

    ret_map = %{data: data}

    backends_to_start = [
      Giraff.TextToSpeechBackend,
      Giraff.VoskSpeechToTextBackend,
      Giraff.SentimentBackend,
      Giraff.SpeechToTextBackend,
      Giraff.EndGameBackend
    ]

    backends_to_start =
      if backends = context[:backends] do
        backends =
          backends
          |> Enum.map(fn backend ->
            case backend do
              %TestBackend{} ->
                start_supervised!(TestBackend.spec(backend))

              %FailTestBackend{} ->
                start_supervised!(FailTestBackend.spec(backend))
            end

            backend.name
          end)
          |> Enum.to_list()

        backends_to_start -- backends
      else
        backends_to_start
      end

    for backend <- backends_to_start do
      start_supervised!(TestBackend.spec(%TestBackend{name: backend}))
    end

    ret_map
  end

  @tag backends: [
         %TestBackend{
           name: TestBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         }
       ]
  test "normal backend" do
    ExUnit.CaptureLog.capture_log(fn ->
      parent = self()

      FLAME.call(TestBackend, fn ->
        send(parent, :ok)
      end)

      assert_receive :ok
    end)
  end

  @tag backends: [
         %FailTestBackend{
           name: Giraff.EndGameBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         }
       ]
  test "fail backend" do
    ExUnit.CaptureLog.capture_log(fn ->
      assert_raise(RuntimeError, ~r/Debug: emulating backend failure/, fn ->
        FLAME.call(Giraff.EndGameBackend, fn ->
          :ok
        end)
      end)
    end)
  end

  test "nominal", %{data: data} do
    ExUnit.CaptureLog.capture_log(fn ->
      res = Giraff.Endpoint.endpoint(data)

      assert res ==
               {:ok,
                %{
                  transcription: " I'm going to be the most wonderful.",
                  sentiment: "Sentiment is positive"
                }}
    end)
  end

  @tag backends: [
         %FailTestBackend{
           name: Giraff.SpeechToTextBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         }
       ]
  test "fail SpeechToTextBackend", %{data: data} do
    ExUnit.CaptureLog.capture_log(fn ->
      res = Giraff.Endpoint.endpoint(data)

      assert res ==
               {:ok,
                %{
                  transcription: "that's wonderful",
                  sentiment: "Sentiment is positive"
                }}
    end)
  end

  @tag backends: [
         %FailTestBackend{
           name: Giraff.SpeechToTextBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         },
         %FailTestBackend{
           name: Giraff.VoskSpeechToTextBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         }
       ]
  test "fail SpeechToTextBackend, and VoskSpeechToTextBackend", %{data: data} do
    ExUnit.CaptureLog.capture_log(fn ->
      res = Giraff.Endpoint.endpoint(data)

      assert {:error, {:process_exited, {:error, {:failed_to_run_function, _}}}} = res
    end)
  end

  @tag backends: [
         %FailTestBackend{
           name: Giraff.SpeechToTextBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         },
         %FailTestBackend{
           name: Giraff.SentimentBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         }
       ]
  test "fail SpeechToTextBackend, and SentimentBackend", %{data: data} do
    ExUnit.CaptureLog.capture_log(fn ->
      res = Giraff.Endpoint.endpoint(data)

      assert res ==
               {:ok,
                %{
                  transcription: "that's wonderful"
                }}
    end)
  end

  @tag backends: [
         %FailTestBackend{
           name: Giraff.EndGameBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         }
       ]
  test "fail EndGameBackend", %{data: data} do
    ExUnit.CaptureLog.capture_log(fn ->
      res = Giraff.Endpoint.endpoint(data)

      assert res ==
               {:ok,
                %{
                  transcription: " I'm going to be the most wonderful.",
                  sentiment: "Sentiment is positive"
                }}
    end)
  end

  @tag backends: [
         %FailTestBackend{
           name: Giraff.EndGameBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         },
         %FailTestBackend{
           name: Giraff.SpeechToTextBackend,
           min: 0,
           max: 1,
           max_concurrency: 10
         }
       ]
  test "fail EndGameBackend, and SpeechToTextBackend", %{data: data} do
    ExUnit.CaptureLog.capture_log(fn ->
      res = Giraff.Endpoint.endpoint(data)

      assert res ==
               {:ok,
                %{
                  transcription: "that's wonderful",
                  sentiment: "Sentiment is positive"
                }}
    end)
  end

  @tag backends: [
         %FailTestBackend{
           name: Giraff.EndGameBackend
         },
         %FailTestBackend{
           name: Giraff.SpeechToTextBackend
         },
         %FailTestBackend{
           name: Giraff.SentimentBackend
         }
       ]
  test "fail EndGameBackend, and SpeechToTextBackend, and SentimentBackend",
       %{data: data} do
    ExUnit.CaptureLog.capture_log(fn ->
      res = Giraff.Endpoint.endpoint(data)

      assert res ==
               {:ok,
                %{
                  transcription: "that's wonderful"
                }}
    end)
  end
end
