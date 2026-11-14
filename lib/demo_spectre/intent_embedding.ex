defmodule DemoSpectre.IntentEmbedding do
  @moduledoc "Deterministic test encoder. Exercises real vector lookup, not neural language quality."
  @behaviour Spectre.Classifier.Embedding
  @groups [
    ~w(stato status avanzamento procede lavoro),
    ~w(aiuto info istruzioni funzioni capacità),
    ~w(memoria ricordi contattato),
    ~w(cronologia history storico)
  ]

  @impl true
  def load(_model, _opts), do: {:ok, 5}

  @impl true
  def embed(text, _opts) do
    words = text |> String.downcase() |> String.split(~r/[^\p{L}]+/u, trim: true)
    index = Enum.find_index(@groups, fn group -> Enum.any?(words, &(&1 in group)) end) || 4
    {:ok, Enum.map(0..4, fn position -> if position == index, do: 1.0, else: -1.0 end)}
  end
end
