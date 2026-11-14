defmodule DemoSpectre.Skills.KnowledgeServer do
  @moduledoc """
  Independent memory and diagnostics through the shared installed Stack.

  This GenServer owns its local state, workers and pending requests. Spectre
  connects it to the root's existing GAM Domain and authority ledger, also used
  by Outreach. Mount permissions restrict its effects and each confirmation
  remains bound to Knowledge's exact presentation.
  """
  use Spectre.Server, tools: DemoSpectre.AI, prompt_root: "priv/prompts"

  @impl true
  def handle_action(%{operation: :forget_memory, args: %{selector: id}}, ctx) do
    # Freeze the selected search result for the presentation, not executor input.
    case Map.fetch(ctx.assigns[:memory_choices] || %{}, id) do
      {:ok, text} -> {:confirm, %{bind: %{selected_text: text}}}
      :error -> {:reject, :search_memory_before_forgetting}
    end
  end

  def handle_action(action, ctx), do: super(action, ctx)

  @impl true
  def handle_flow({:knowledge, :recall}, input, ctx) do
    DemoSpectre.Routing.record(ctx)
    query = input.text |> String.replace(~r/\Amemoria\s*/i, "") |> String.trim()
    query = if query == "", do: "contattato sito email nota", else: query
    mnemonic(ctx, {:recall, query}, on_result: :recalled)
  end

  # Operation arguments/options belong in the tuple; callback options stay outside.
  def handle_flow({:knowledge, :search}, input, ctx),
    do: mnemonic(ctx, {:search, strip_command(input.text), limit: 5}, on_result: :searched)

  def handle_flow({:knowledge, :reflect}, input, ctx),
    do:
      mnemonic(ctx, {:reflect, strip_command(input.text), max_tokens: 1200},
        on_result: :reflected
      )

  def handle_flow({:knowledge, :atlas}, _, ctx),
    do: mnemonic(ctx, {:atlas, max_nodes: 20}, on_result: :atlas)

  def handle_flow({:knowledge, :knowledge}, _, ctx),
    do: mnemonic(ctx, {:knowledge}, on_result: :knowledge)

  def handle_flow({:knowledge, :learn}, input, ctx),
    do: mnemonic(ctx, {:learn, strip_command(input.text)}, on_result: :learned)

  def handle_flow({:knowledge, :forget}, input, ctx),
    do: mnemonic(ctx, {:forget, strip_command(input.text)}, on_result: :forgotten)

  def handle_flow({:knowledge, :log_hello}, _, ctx),
    do: generate(ctx, :hello, on_result: :hello_model)

  def handle_flow({:knowledge, :remember}, input, ctx),
    do:
      mnemonic(ctx, {:remember, Regex.replace(~r/^ricorda\s+/i, input.text, "")},
        on_result: :saved
      )

  def handle_flow({:knowledge, :diagnostics}, _, ctx),
    do: beam(ctx, {:endpoints}, on_result: :channels)

  def handle_flow({:knowledge, :notice}, _, ctx),
    do:
      beam(
        ctx,
        {:deliver, :email,
         %{to: "owner@demo.local", content: %{type: :text, text: "La Skill Memoria è operativa."}}},
        on_result: :notified
      )

  def handle_flow({:knowledge, :resume}, _, ctx), do: DemoSpectre.Pending.resume(ctx)

  def handle_flow(_, _, ctx),
    do:
      respond(
        ctx,
        "Memoria disponibile. Usa memoria, ricorda, diagnostica, notifica o riprendi memoria."
      )

  @impl true
  def handle_pending(pending, input, ctx), do: DemoSpectre.Pending.handle(pending, input, ctx)
  @impl true
  def handle_info(:refresh, ctx),
    do: {:noreply, respond(ctx, "Refresh ricevuto tramite handle_info nel processo della Skill.")}

  @impl true
  def handle_result(
        :pending_lifecycle,
        {:pending_lifecycle, %{kind: :close, status: :applied}},
        ctx
      ),
      do:
        ctx
        |> assign(:job_active, false)
        |> respond("Richiesta chiusa per scadenza. GAM ha registrato il cambio di stato.")

  def handle_result(:pending_lifecycle, {:pending_lifecycle, _}, ctx), do: no_response(ctx)

  def handle_result(tag, result, ctx) do
    DemoSpectre.Events.record_result(ctx.identity.subject, tag, result)

    DemoSpectre.Events.publish(ctx.identity.subject, :tool, %{
      skill: :knowledge,
      tool: tool(tag),
      result: inspect(result, limit: 12, printable_limit: 800)
    })

    next(tag, result, ctx)
  end

  @spec next(atom(), term(), Spectre.Server.Context.t()) :: Spectre.Server.Context.t()
  defp next(:hello_model, {:generated, response}, ctx),
    do: kinetic(ctx, response, on_result: :hello_plan)

  defp next(:hello_plan, {:prepared, %{actions: [proposal]}}, ctx),
    do:
      propose(ctx, proposal.operation, proposal.args,
        proposal_metadata: proposal.metadata,
        on_result: :hello_logged
      )

  defp next(:searched, {:ok, results}, ctx) do
    DemoSpectre.Events.publish(ctx.identity.subject, :memory_results, %{results: results})

    text =
      Enum.map_join(results, "\n\n", fn result ->
        "• #{Map.get(result.record, :text, "")}"
      end)

    respond(
      assign(ctx, :memory_choices, Map.new(results, &{&1.id, Map.get(&1.record, :text, "")})),
      if(text == "", do: "Nessun ricordo trovato.", else: "Risultati della ricerca:\n" <> text)
    )
  end

  defp next(:reflected, {:ok, packet}, ctx),
    do:
      respond(
        ctx,
        "Contesto con fonti:\n" <>
          memory_text(%{moments: packet.raw_memories}) <>
          "\n#{length(packet.observations)} osservazioni · #{length(packet.mental_models)} modelli mentali"
      )

  defp next(:atlas, {:ok, atlas}, ctx),
    do:
      respond(
        ctx,
        "Mappa memoria: #{length(atlas.nodes)} nodi, #{length(atlas.edges)} collegamenti."
      )

  defp next(:knowledge, {:ok, knowledge}, ctx),
    do:
      respond(
        ctx,
        "Conoscenze riutilizzabili:\n" <>
          inspect(knowledge.skills, pretty: true, printable_limit: 2000)
      )

  defp next(:channels, {:ok, _}, ctx), do: pulse(ctx, {:protocol}, on_result: :protocol)
  defp next(:protocol, {:ok, _}, ctx), do: ledger(ctx, {:head}, on_result: :checkpoint)

  defp next(:checkpoint, {:ok, _}, ctx),
    do: lab(ctx, {:inspect, :checkpoint}, on_result: :inspection)

  defp next(:inspection, {:ok, %{codec_valid: true}}, ctx),
    do:
      respond(
        ctx,
        "Diagnostica completata: Beam e Pulse disponibili, checkpoint Ledger leggibile e codifica verificata da Lab."
      )

  defp next(:recalled, {:ok, memory}, ctx),
    do:
      respond(
        ctx,
        "Memoria della sessione:\n" <>
          memory_text(memory)
      )

  defp next(tag, {:governed, %{outcome: %{status: :succeeded}}}, ctx) do
    text =
      case tag do
        :saved -> "Nota salvata dopo conferma."
        :forgotten -> "Ricordo dimenticato dopo conferma. Le ricerche ordinarie lo escludono."
        :learned -> "Conoscenza salvata dopo conferma."
        :hello_logged -> "hello scritto nel log dopo conferma."
        :notified -> "Notifica Beam accettata nella casella locale."
      end

    respond(ctx, text)
  end

  defp next(_, {:consent, status}, ctx),
    do: respond(ctx, "Richiesta chiusa: #{status}. Nessuna nuova scrittura.")

  defp next(tag, result, ctx),
    do: respond(ctx, "Operazione #{tag}: #{inspect(result, limit: 6, printable_limit: 350)}")

  @spec memory_text(map()) :: String.t()
  defp memory_text(memory) do
    texts = Enum.map(Map.get(memory, :moments, []), & &1.text) |> Enum.uniq()

    if texts == [],
      do:
        "Nessuna informazione richiamata per questa ricerca. Prova memoria seguito da parole della nota, oppure ricorda per salvarne una.",
      else: Enum.map_join(texts, "\n\n", &("• " <> &1))
  end

  @spec tool(atom()) :: atom()
  defp tool(tag),
    do:
      Map.get(
        %{
          channels: :beam,
          protocol: :pulse,
          checkpoint: :ledger,
          inspection: :lab,
          hello_model: :prism,
          hello_plan: :kinetic,
          hello_logged: :kinetic,
          searched: :mnemonic,
          reflected: :mnemonic,
          atlas: :mnemonic,
          knowledge: :mnemonic,
          learned: :mnemonic,
          forgotten: :mnemonic,
          recalled: :mnemonic,
          saved: :mnemonic,
          notified: :beam
        },
        tag,
        tag
      )

  @spec strip_command(String.t()) :: String.t()
  defp strip_command(text), do: Regex.replace(~r/^\S+\s+/u, text, "")
end
