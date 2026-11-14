defmodule DemoSpectre.AgentServer do
  @moduledoc "The host conversation stays available while mounted Skills do their work."
  use Spectre.Server, tools: DemoSpectre.AI
  @impl true
  def handle_flow({:assistant, :status}, _, ctx) do
    DemoSpectre.Routing.record(ctx)

    respond(
      ctx,
      "Agente disponibile. Ricerca e Memoria lavorano in processi separati: puoi usarle anche mentre una conferma è aperta."
    )
  end

  def handle_flow({:assistant, :history}, _, ctx) do
    DemoSpectre.Routing.record(ctx)

    effects =
      DemoSpectre.Events.history(ctx.identity.subject) |> Enum.count(&(&1.kind == :effect))

    respond(
      ctx,
      "Cronologia della sessione: #{effects} esiti locali. Il pannello GAM mostra il registro autorevole; la casella mostra i messaggi accettati."
    )
  end

  def handle_flow(_, _, ctx),
    do:
      respond(
        ctx,
        "Apri la pagina di esempio, oppure scrivi memoria, diagnostica, notifica o ricorda seguito da una nota. Usa i pulsanti sulla richiesta per confermare la Skill corretta."
      )
end
