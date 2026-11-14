defmodule DemoSpectre.Knowledge.Memory do
  @moduledoc "Memory result presentation; orchestration and governed effects stay in KnowledgeServer."

  @doc "Formats recalled moments without repeating identical memories."
  @spec recall(map()) :: String.t()
  def recall(memory) do
    texts = Enum.map(Map.get(memory, :moments, []), & &1.text) |> Enum.uniq()

    if texts == [],
      do:
        "Nessuna informazione richiamata per questa ricerca. Prova memoria seguito da parole della nota, oppure ricorda per salvarne una.",
      else: Enum.map_join(texts, "\n\n", &("• " <> &1))
  end

  @doc "Keeps exact search selections for a later forget presentation."
  @spec choices([map()]) :: map()
  def choices(results), do: Map.new(results, &{&1.id, Map.get(&1.record, :text, "")})

  @doc "Formats search results."
  @spec search([map()]) :: String.t()
  def search([]), do: "Nessun ricordo trovato."

  def search(results),
    do:
      "Risultati della ricerca:\n" <>
        Enum.map_join(results, "\n\n", &("• " <> Map.get(&1.record, :text, "")))

  @doc "Formats reflected memory and derived context counts."
  @spec reflection(map()) :: String.t()
  def reflection(packet),
    do:
      "Contesto con fonti:\n" <>
        recall(%{moments: packet.raw_memories}) <>
        "\n#{length(packet.observations)} osservazioni · #{length(packet.mental_models)} modelli mentali"

  @doc "Summarizes the memory graph."
  @spec atlas(map()) :: String.t()
  def atlas(atlas),
    do: "Mappa memoria: #{length(atlas.nodes)} nodi, #{length(atlas.edges)} collegamenti."

  @doc "Formats reusable knowledge within the demo's display limit."
  @spec knowledge(map()) :: String.t()
  def knowledge(knowledge),
    do:
      "Conoscenze riutilizzabili:\n" <>
        inspect(knowledge.skills, pretty: true, printable_limit: 2000)

  @doc "Returns text only for known memory continuations."
  @spec success(term()) :: {:ok, String.t()} | :unknown
  def success(:saved), do: {:ok, "Nota salvata dopo conferma."}

  def success(:forgotten),
    do: {:ok, "Ricordo dimenticato dopo conferma. Le ricerche ordinarie lo escludono."}

  def success(:learned), do: {:ok, "Conoscenza salvata dopo conferma."}
  def success(_), do: :unknown
end
