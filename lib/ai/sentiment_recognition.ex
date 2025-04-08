defmodule AI.SentimentRecognition do
  require Logger

  @spec setup() :: {:error, :setup_failed} | {:ok, Nx.Serving.t()}
  def setup do
    with {:ok, model_info} <- Bumblebee.load_model({:local, System.get_env("BERT_TWEETER_DIR")}),
         {:ok, tokenizer} <-
           Bumblebee.load_tokenizer({:local, System.get_env("BERT_TWEETER_DIR")}),
         serving <-
           Bumblebee.Text.text_classification(
             model_info,
             tokenizer,
             defn_options: [compiler: EXLA]
           ) do
      {:ok, serving}
    else
      error ->
        Logger.error("Failed to setup BERT Tweeter: #{inspect(error)}")
        {:error, :setup_failed}
    end
  end

  @spec analyze_text(String.t()) ::
          {:error, :invalid_response} | {:ok, %{label: String.t(), score: number()}}
  def analyze_text(text) do
    serving = AI.SentimentServer.get_serving()

    res = Nx.Serving.run(serving, text)

    Logger.debug("Sentiment analysis result: #{inspect(res)}")

    case res do
      %{predictions: predictions} when is_list(predictions) ->
        neg_score = (Enum.find(predictions, &(&1.label == "LABEL_0")) || %{score: 0}).score
        pos_score = (Enum.find(predictions, &(&1.label == "LABEL_1")) || %{score: 0}).score

        {score, label} =
          Enum.max([
            {neg_score, "NEG"},
            {pos_score, "POS"}
          ])

        {:ok, %{label: label, score: score}}

      args ->
        Logger.error("Unexpected response format: #{inspect(res)} with args: #{inspect(args)}")
        {:error, :invalid_response}
    end
  end
end
