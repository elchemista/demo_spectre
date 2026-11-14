defmodule DemoSpectre.OpenRouter do
  @moduledoc "Optional non-streaming OpenRouter transport, enabled explicitly through runtime environment."
  @doc "Calls Chat Completions; credentials never enter prompts, checkpoints or UI events."
  @spec complete(String.t()) :: {:ok, String.t()} | {:error, term()}
  def complete(prompt) do
    key = System.get_env("OPENROUTER_API_KEY")
    model = System.get_env("OPENROUTER_MODEL")

    if is_binary(key) and key != "" and is_binary(model) and model != "" do
      result =
        Req.post("https://openrouter.ai/api/v1/chat/completions",
          auth: {:bearer, key},
          json: %{
            model: model,
            messages: [%{role: "user", content: prompt}],
            temperature: 0,
            max_tokens: 600
          },
          receive_timeout: 45_000,
          retry: false
        )

      case result do
        {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => text}} | _]}}}
        when is_binary(text) ->
          {:ok, text}

        {:ok, %{status: status}} ->
          {:error, {:openrouter_http, status}}

        {:error, _} ->
          {:error, :openrouter_transport_failed}
      end
    else
      {:error, :openrouter_configuration_missing}
    end
  end
end
