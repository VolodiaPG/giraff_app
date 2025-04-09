defmodule SentimentAnalysisTest do
  use ExUnit.Case
  doctest FLAMERetry

  require Logger

  setup_all do
    pid =
      start_supervised!(
        {FLAME.Pool,
         name: Giraff.SentimentBackend,
         backend: FLAME.LocalBackend,
         min: 0,
         max: 1,
         max_concurrency: 10}
      )

    %{pool: pid}
  end

  test "nominal" do
    text = "I'm very happy today"

    result =
      Giraff.SentimentAnalysis.analyze_sentiment(text)

    assert {:ok, sentiment} = result
    assert is_map(sentiment)
    assert sentiment.label == "POS"
    assert sentiment.score >= 0.99
  end

  test "nominal, callback" do
    caller = self()
    text = "I'm very happy today"

    result =
      Giraff.SentimentAnalysis.analyze_sentiment(text, fn sentiment ->
        send(
          caller,
          sentiment
        )
      end)

    assert {:ok, sentiment} = result
    assert is_map(sentiment)
    assert sentiment.label == "POS"
    assert sentiment.score >= 0.99

    assert_receive {:ok, ^sentiment}
  end

  test "nominal with local backend" do
    text = "I'm very happy today"

    result =
      apply(FLAME.Pool, :call, Giraff.SentimentAnalysis.remote_analyze_sentiment_spec(text, []))

    assert {:ok, sentiment} = result
    assert is_map(sentiment)
    assert sentiment.label == "POS"
    assert sentiment.score >= 0.99
  end

  test "degraded sentiment analysis" do
    text = "I'm very happy today"
    result = Giraff.SentimentAnalysis.degraded_sentiment_analysis(text)
    assert {:ok, %{label: "NEG"}} = result
  end

  test "degraded sentiment analysis, callback" do
    caller = self()
    text = "I'm very happy today"

    result =
      Giraff.SentimentAnalysis.degraded_sentiment_analysis(text, fn
        sentiment ->
          send(caller, sentiment)
      end)

    assert {:ok, %{label: "NEG"}} = result
    assert_receive {:ok, %{label: "NEG"}}
  end
end
