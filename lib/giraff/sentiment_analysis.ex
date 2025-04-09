defmodule Giraff.SentimentAnalysis do
  @moduledoc """
  Sentiment analysis module to be used by the Giraff app
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def analyze_sentiment(text, after_callback \\ nil) when is_binary(text) do
    with sentiment = {:ok, result} when is_map(result) <-
           AI.SentimentRecognition.analyze_text(text) do
      Logger.debug("Sentiment analysis result: #{inspect(sentiment)}")
      Tracer.add_event("sentiment_analyzed", %{sentiment: inspect(sentiment)})
      if after_callback, do: after_callback.(sentiment)

      sentiment
    else
      error ->
        Tracer.add_event("sentiment_analysis.error", %{reason: error})
        Logger.error("Sentiment analysis failed: #{inspect(error)}")
        Tracer.add_event("sentiment_analysis_failed", %{error: inspect(error)})
        {:error, {:sentiment_analysis_failed, error}}
    end
  end

  @doc """
  Outputs the settings to call the function on the appropriate FLAME backend
  """
  def remote_analyze_sentiment_spec(text, opts) when is_binary(text) do
    Keyword.put_new(opts, :retries, 2)

    [
      Giraff.SentimentBackend,
      fn ->
        __MODULE__.analyze_sentiment(
          text,
          Keyword.get(
            opts,
            :after_callback
          )
        )
      end,
      opts
    ]
  end

  @doc """
  Fallback function for sentiment analysis
  """
  def degraded_sentiment_analysis(text, after_callback \\ nil) when is_binary(text) do
    Logger.warning("Sentiment analysis could not be called, using degraded function")
    Tracer.add_event("using_degraded_sentiment_analysis", %{})

    res =
      {:ok, %{label: "NEG"}}

    if after_callback, do: after_callback.(res)

    res
  end
end
