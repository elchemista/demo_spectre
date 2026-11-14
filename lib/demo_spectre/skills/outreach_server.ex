defmodule DemoSpectre.Skills.OutreachServer do
  @moduledoc """
  Lens → model → Kinetic proposal → GAM consent → local email → consent to remember.

  Runs in its own GenServer with local state and pending intentions, using the
  root AgentServer's same automatic GAM Domain and ledger. The email and memory
  write require separate presentations and decisions; Knowledge's consent cannot
  authorize either request.
  """
  use Spectre.Server, tools: DemoSpectre.AI, prompt_root: "priv/prompts"

  @impl true
  def handle_action(%{operation: {_, :kinetic, :send_email}, args: %{"to" => to}}, ctx) do
    # This is a business rule; Spectre supplies the Candidate and consent protocol.
    case ctx.assigns[:contact] do
      %{email: ^to} = contact -> {:confirm, %{bind: %{observed_contact: contact}}}
      _ -> {:reject, :recipient_does_not_match_observed_contact}
    end
  end

  def handle_action(action, ctx), do: super(action, ctx)

  @impl true
  def handle_flow({:outreach, :new_link}, _, %{assigns: %{job_active: true}} = ctx),
    do:
      respond(
        ctx,
        "C’è già una ricerca aperta. Concludi o annulla la richiesta prima di avviarne un’altra."
      )

  def handle_flow({:outreach, :new_link}, input, ctx) do
    ctx
    |> assign(:job_active, true)
    |> assign(:contact, nil)
    |> assign(:email, nil)
    |> assign(:url, input.text)
    |> directive(
      {:new, %{mission: "Visit the page and prepare a contact email", reasoner: :model}},
      on_result: :task
    )
  end

  def handle_flow({:outreach, :status}, _, ctx),
    do:
      respond(
        ctx,
        "La ricerca resta aperta. Una richiesta sospesa scade dopo 30 secondi; puoi riprenderla prima della scadenza."
      )

  def handle_flow({:outreach, :resume}, _, ctx), do: DemoSpectre.Pending.resume(ctx)

  def handle_flow(_, _, ctx),
    do:
      respond(
        ctx,
        "Questa Skill accetta il link della pagina di esempio, stato ricerca o riprendi ricerca."
      )

  @impl true
  def handle_pending(pending, input, ctx), do: DemoSpectre.Pending.handle(pending, input, ctx)
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
      skill: :outreach,
      tool: tool(tag),
      result: inspect(result, limit: 12, printable_limit: 800)
    })

    next(tag, result, ctx)
  end

  @spec next(atom(), term(), Spectre.Server.Context.t()) :: Spectre.Server.Context.t()
  defp next(:task, {:directive, _}, ctx),
    do: prism(ctx, %{purpose: :response_generation}, on_result: :selected)

  defp next(:selected, {:selected, _}, ctx),
    do: mnemonic(ctx, {:recall, "contattato " <> ctx.assigns.url}, on_result: :memory)

  defp next(:memory, {:ok, memories}, ctx) do
    contacted? =
      Enum.any?(Map.get(memories, :moments, []), fn moment ->
        String.contains?(moment.text, "Contattato ") and
          String.contains?(moment.text, ctx.assigns.url)
      end)

    if contacted? do
      respond(
        assign(ctx, :job_active, false),
        "Questo sito risulta già contattato nella memoria della sessione. Nessuna nuova email proposta."
      )
    else
      ctx |> assign(:memories, memories) |> lens({:open, ctx.assigns.url}, on_result: :opened)
    end
  end

  defp next(:opened, {:ok, tab}, ctx),
    do: ctx |> assign(:tab, tab) |> lens({:look, tab}, on_result: :looked)

  defp next(:looked, {:ok, page}, ctx),
    do: ctx |> assign(:page, page) |> lens({:close, ctx.assigns.tab}, on_result: :closed)

  defp next(:closed, {:ok, _}, ctx) do
    ctx = assign(ctx, :tab, nil)

    case DemoSpectre.Contacts.select(ctx.assigns.page) do
      {:ok, %{email: email} = contact} ->
        stream? =
          Application.get_env(:demo_spectre, :model_mode, :deterministic) == :deterministic

        ctx
        |> assign(:contact, contact)
        |> assign(:email, email)
        |> generate(:contact,
          assigns: %{email: email, page: ctx.assigns.page, memories: ctx.assigns.memories},
          stream: stream?,
          stream_adapter: DemoSpectre.Stream,
          preview: :auto,
          on_result: :model
        )

      {:error, :contact_missing} ->
        respond(
          assign(ctx, :job_active, false),
          "La pagina non contiene un indirizzo email. Nessuna azione proposta."
        )

      {:error, {:ambiguous_contacts, contacts}} ->
        ctx
        |> assign(:job_active, false)
        |> assign(:contact, nil)
        |> respond(
          "La pagina contiene #{length(contacts)} contatti distinti. Non scelgo automaticamente il destinatario; nessuna email proposta."
        )

      {:error, :invalid_page} ->
        ctx
        |> assign(:job_active, false)
        |> assign(:contact, nil)
        |> respond(
          "La pagina non contiene una fonte verificabile per il contatto. Nessuna email proposta."
        )
    end
  end

  defp next(:model, {:generated, response}, ctx), do: kinetic(ctx, response, on_result: :planned)

  defp next(:planned, {:prepared, %{actions: [proposal]}}, ctx),
    do:
      propose(ctx, proposal.operation, proposal.args,
        proposal_metadata: proposal.metadata,
        on_result: :sent
      )

  defp next(:sent, {:governed, %{outcome: %{status: :succeeded}}}, ctx) do
    ctx
    |> respond(
      "Email accettata nella casella locale. Ora ti chiedo separatamente se ricordare il risultato."
    )
    |> mnemonic(
      {:remember,
       "Contattato #{ctx.assigns.email} dal sito #{ctx.assigns.url}. Email nella casella locale."},
      on_result: :saved
    )
  end

  defp next(:saved, {:governed, %{outcome: %{status: :succeeded}}}, ctx),
    do:
      respond(
        assign(ctx, :job_active, false),
        "Risultato salvato con il tuo consenso. Scrivi memoria per richiamarlo dall’altra Skill."
      )

  defp next(_, {:consent, status}, ctx),
    do:
      respond(
        assign(ctx, :job_active, false),
        "Richiesta chiusa: #{status}. L’operazione in attesa non è stata eseguita."
      )

  defp next(:cleanup, _result, ctx), do: no_response(ctx)

  defp next(tag, result, ctx) do
    ctx =
      if tab = ctx.assigns[:tab] do
        ctx |> assign(:tab, nil) |> lens({:close, tab}, on_result: :cleanup)
      else
        ctx
      end

    respond(
      assign(ctx, :job_active, false),
      "Operazione #{tag} fermata: #{inspect(result, limit: 6, printable_limit: 350)}"
    )
  end

  @spec tool(atom()) :: atom()
  defp tool(tag),
    do:
      Map.get(
        %{
          task: :directive,
          selected: :prism,
          memory: :mnemonic,
          opened: :lens,
          looked: :lens,
          closed: :lens,
          model: :model,
          planned: :kinetic,
          sent: :gam,
          saved: :mnemonic
        },
        tag,
        tag
      )
end
