defmodule DemoSpectre.Model do
  @moduledoc "Deterministic provider by default; optional OpenRouter configuration is read at runtime."
  @doc "Completes the rendered prompt through the selected demo mode."
  @spec complete(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def complete(prompt, _opts) do
    case Application.get_env(:demo_spectre, :model_mode, :deterministic) do
      :deterministic -> deterministic(prompt)
      :openrouter -> DemoSpectre.OpenRouter.complete(prompt)
    end
  end

  @doc "Creates Action Language only after the page context has been supplied."
  @spec deterministic(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def deterministic("DEMO_LOG_HELLO" <> _rest),
    do:
      {:ok,
       "Propongo di scrivere hello nel log. Attendo conferma. <al>LOG HELLO MESSAGE=\"hello\"</al>"}

  def deterministic(prompt) do
    case Regex.run(~r/CONTACT_EMAIL=([^\s]+)/, prompt, capture: :all_but_first) do
      [email] ->
        body = "Ciao, ho visitato il vostro sito. Mi piacerebbe conoscere i vostri progetti."

        {:ok,
         "Ho trovato il contatto e preparato un messaggio. Attendo la tua conferma prima di inviarlo.\n" <>
           "<al>SEND EMAIL TO=" <>
           Jason.encode!(email) <> " BODY=" <> Jason.encode!(body) <> "</al>"}

      _ ->
        {:error, :contact_missing}
    end
  end
end
