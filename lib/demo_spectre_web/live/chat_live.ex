defmodule DemoSpectreWeb.ChatLive do
  @moduledoc "Live showcase of one Agent, two Skill processes and their shared GAM Domain."
  use DemoSpectreWeb, :live_view
  alias DemoSpectre.{Events, Session}
  alias Spectre.Server
  @skills %{"outreach" => :outreach, "knowledge" => :knowledge}
  @tools ~w(lens kinetic mnemonic prism beam directive pulse ledger lab)

  @impl true
  def mount(_, _, socket) do
    socket =
      socket
      |> assign(
        page_title: "Spectre Playground",
        current_scope: nil,
        session: nil,
        agent: nil,
        session_id: nil,
        domain: "In attesa di connessione",
        target: "agent",
        mode: Application.get_env(:demo_spectre, :model_mode),
        form: to_form(%{"text" => ""}, as: :chat),
        previews: %{},
        skills: %{},
        pending: [],
        tool_hits: MapSet.new(),
        tools: @tools,
        revision: 0,
        act_count: 0,
        outcome_count: 0,
        tab: "activity",
        memory_form: to_form(%{"query" => "Elixir", "operation" => "search"}, as: :memory),
        memory_ids: MapSet.new(),
        last_route: nil,
        messages_count: 0,
        presentations: MapSet.new(),
        last_revision: nil,
        gam_cursor: nil,
        operational: %{},
        refresh_scheduled: false,
        error: nil
      )
      |> stream(:messages, [])
      |> stream(:activity, [])
      |> stream(:mailbox, [])
      |> stream(:memory_results, [])
      |> stream(:logs, [])
      |> stream(:records, [])

    if connected?(socket) do
      case Session.start(self()) do
        {:ok, session} ->
          Process.monitor(session)
          info = Session.info(session)
          Phoenix.PubSub.subscribe(DemoSpectre.PubSub, Events.topic(info.id))
          send(self(), :diagnostics_changed)

          {:ok,
           socket
           |> assign(
             session: session,
             agent: info.agent,
             session_id: info.id,
             domain: info.domain
           )
           |> message(
             "agent",
             "Benvenuto. Apri il sito di esempio: la Skill Ricerca preparerà un’email. Nel frattempo puoi usare Memoria o avviare la diagnostica."
           )}

        {:error, _} ->
          {:ok,
           assign(
             socket,
             :error,
             "Avvio non riuscito. Controlla il log del server e la disponibilità di Lightpanda."
           )}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event(_event, _params, %{assigns: %{session: nil}} = socket), do: {:noreply, socket}

  def handle_event("draft", %{"chat" => %{"text" => text}}, socket)
      when is_binary(text) and byte_size(text) <= 4000,
      do: {:noreply, assign(socket, :form, to_form(%{"text" => text}, as: :chat))}

  def handle_event("send", %{"chat" => %{"text" => text}}, socket) when is_binary(text) do
    text = String.trim(text)

    if text == "" or byte_size(text) > 4000 do
      {:noreply, put_flash(socket, :error, "Scrivi un messaggio di massimo 4.000 byte.")}
    else
      {:noreply,
       socket
       |> submit(text, socket.assigns.target)
       |> assign(:form, to_form(%{"text" => ""}, as: :chat))}
    end
  end

  def handle_event("target", %{"target" => target}, socket)
      when target in ["agent", "outreach", "knowledge"],
      do: {:noreply, assign(socket, :target, target)}

  def handle_event("quick", %{"command" => command}, socket) do
    commands = %{
      "visit" => {fixture_url("studio"), "agent"},
      "empty" => {fixture_url("no-email"), "agent"},
      "diagnostics" => {"diagnostica", "agent"},
      "memory" => {"memoria", "agent"},
      "hello" => {"hello", "agent"},
      "cache" => {"come procede il lavoro?", "agent"},
      "atlas" => {"mappa memoria", "agent"},
      "knowledge" => {"conoscenze", "agent"},
      "note" => {"ricorda Preferisco siti realizzati in Elixir.", "agent"},
      "notice" => {"notifica", "agent"},
      "status" => {"status", "agent"},
      "suspend" => {"stato ricerca", "outreach"},
      "resume" => {"riprendi ricerca", "outreach"}
    }

    case commands[command] do
      {text, target} -> {:noreply, submit(socket, text, target)}
      nil -> {:noreply, socket}
    end
  end

  def handle_event(
        "memory_query",
        %{"memory" => %{"query" => query, "operation" => operation}},
        socket
      )
      when is_binary(query) and byte_size(query) in 1..2000 and
             operation in ["search", "recall", "reflect"] do
    command = %{"search" => "cerca", "recall" => "memoria", "reflect" => "rifletti"}[operation]

    socket =
      assign(
        socket,
        :memory_form,
        to_form(%{"query" => query, "operation" => operation}, as: :memory)
      )

    {:noreply, submit(socket, command <> " " <> query, "knowledge")}
  end

  def handle_event("forget_memory", %{"id" => id}, socket) when is_binary(id) do
    if MapSet.member?(socket.assigns.memory_ids, id),
      do: {:noreply, submit(socket, "dimentica " <> id, "knowledge")},
      else:
        {:noreply,
         put_flash(socket, :error, "Ricordo non presente nei risultati di questa sessione.")}
  end

  def handle_event(
        "confirm",
        %{
          "skill" => skill,
          "id" => id,
          "revision" => revision,
          "presentation" => presentation,
          "answer" => answer
        },
        socket
      )
      when is_binary(skill) and is_binary(id) and is_binary(revision) and
             is_binary(presentation) and byte_size(revision) <= 20 do
    with {:ok, mount} <- Map.fetch(@skills, skill),
         {number, ""} <- Integer.parse(revision),
         true <- answer in ["confermo", "annulla"],
         true <-
           Enum.any?(
             socket.assigns.pending,
             &(&1.skill == mount and &1.id == id and &1.revision == number and
                 &1.status == :foreground and &1.presentation.ref == presentation)
           ) do
      decision = if answer == "confermo", do: :confirm, else: :reject

      case Session.decide(socket.assigns.session, mount, presentation, decision) do
        {:ok, _} ->
          {:noreply, message(socket, "user", "#{answer} · #{label(mount)}")}

        {:error, _} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Questa richiesta è cambiata: attendi la nuova presentazione."
           )}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Conferma scaduta o non più valida.")}
    end
  end

  def handle_event("presented", %{"ref" => ref}, socket) when is_binary(ref) do
    if MapSet.member?(socket.assigns.presentations, ref),
      do: Session.presented(socket.assigns.session, ref)

    {:noreply, assign(socket, :presentations, MapSet.delete(socket.assigns.presentations, ref))}
  end

  def handle_event("tab", %{"tab" => tab}, socket)
      when tab in ["activity", "gam", "mailbox", "memory", "logs"],
      do: {:noreply, assign(socket, :tab, tab)}

  def handle_event("refresh_skill", _, socket) do
    with {:ok, skill} <- Server.skill_server(socket.assigns.agent, :knowledge),
         do: send(skill, :refresh)

    {:noreply, socket}
  end

  def handle_event("more_records", _, %{assigns: %{gam_cursor: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("more_records", _, socket) do
    case Session.gam_page(socket.assigns.session, socket.assigns.gam_cursor) do
      {:ok, page} ->
        {:noreply,
         socket
         |> stream(:records, record_rows(page.records), limit: -200)
         |> assign(:gam_cursor, page.next_cursor)}

      {:error, :stale_cursor} ->
        {:noreply, schedule_refresh(socket)}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Registro non disponibile. Riprova dopo il prossimo aggiornamento."
         )}
    end
  end

  def handle_event(_, _, socket),
    do:
      {:noreply,
       put_flash(socket, :error, "Richiesta non valida. La sessione resta disponibile.")}

  @impl true
  def handle_info(:diagnostics_changed, socket), do: {:noreply, schedule_refresh(socket)}

  def handle_info(:refresh, %{assigns: %{session: nil}} = socket), do: {:noreply, socket}

  def handle_info(:refresh, socket) do
    socket = assign(socket, :refresh_scheduled, false)

    case Session.snapshot(socket.assigns.session) do
      {:error, _} -> {:noreply, disconnected(socket)}
      snapshot -> {:noreply, refresh_snapshot(socket, snapshot)}
    end
  catch
    :exit, {:timeout, _} ->
      {:noreply, schedule_refresh(assign(socket, :refresh_scheduled, false))}

    :exit, _ ->
      {:noreply, disconnected(socket)}
  end

  def handle_info({:presentation, show}, socket) do
    ref = show["presentation_ref"]

    item = %{
      id: "show-" <> ref,
      source: "gam",
      body: show["rendered_payload"],
      kind: :presentation,
      ref: ref
    }

    {:noreply,
     socket
     |> assign(:presentations, MapSet.put(socket.assigns.presentations, ref))
     |> stream_insert(:messages, item, limit: -150)}
  end

  def handle_info({:agent_event, {:skill, skill, event}}, socket),
    do: {:noreply, agent_event(socket, skill, event)}

  def handle_info({:agent_event, event}, socket),
    do: {:noreply, agent_event(socket, :agent, event)}

  def handle_info({:demo_event, event}, socket) do
    item =
      Map.put(event, :text, inspect(event.data, pretty: true, limit: 15, printable_limit: 1800))

    socket = stream_insert(socket, :activity, item, at: 0, limit: 150)

    socket =
      case event do
        %{kind: :routing, data: route} ->
          assign(socket, :last_route, route)

        %{kind: :memory_results, data: %{results: results}} ->
          rows =
            Enum.map(results, fn result ->
              %{id: result.id, text: Map.get(result.record, :text, ""), source: result.source}
            end)

          socket
          |> stream(:memory_results, rows, reset: true)
          |> assign(:memory_ids, MapSet.new(Enum.map(rows, & &1.id)))
          |> assign(:tab, "memory")

        %{kind: :effect, data: %{class: "demo.forget", payload: %{"payload" => %{selector: id}}}} ->
          socket
          |> stream_delete(:memory_results, %{id: id})
          |> assign(:memory_ids, MapSet.delete(socket.assigns.memory_ids, id))

        %{kind: :effect, data: %{class: "demo.log"}} ->
          socket |> stream_insert(:logs, item) |> assign(:tab, "logs")

        %{kind: :tool, data: %{tool: tool}} ->
          assign(socket, :tool_hits, MapSet.put(socket.assigns.tool_hits, to_string(tool)))

        %{kind: :effect, data: %{class: class}} when class in ["demo.email", "demo.beam"] ->
          stream_insert(socket, :mailbox, item, at: 0, limit: 100)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_info({:DOWN, _, :process, session, _}, %{assigns: %{session: session}} = socket),
    do: {:noreply, disconnected(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  @spec disconnected(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp disconnected(socket) do
    assign(socket,
      error: "Sessione terminata. Ricarica la pagina per iniziare una nuova sessione.",
      session: nil,
      agent: nil,
      pending: [],
      previews: %{},
      presentations: MapSet.new()
    )
  end

  @spec refresh_snapshot(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp refresh_snapshot(socket, snapshot) do
    pending =
      Enum.flat_map(snapshot.skills, fn {skill, state} ->
        Enum.map(state.pending, &Map.put(&1, :skill, skill))
      end)

    gam = snapshot.gam

    socket =
      assign(socket,
        skills: snapshot.skills,
        pending: pending,
        revision: gam.revision,
        act_count: Map.get(gam.counts, :acts, 0),
        outcome_count: Map.get(gam.counts, :outcomes, 0),
        operational: snapshot.root
      )

    socket =
      if gam.revision != socket.assigns.last_revision do
        socket
        |> stream(:records, record_rows(gam.records), reset: true)
        |> assign(last_revision: gam.revision, gam_cursor: gam.next_cursor)
      else
        socket
      end

    socket
  end

  @spec schedule_refresh(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp schedule_refresh(%{assigns: %{session: nil}} = socket), do: socket
  defp schedule_refresh(%{assigns: %{refresh_scheduled: true}} = socket), do: socket

  defp schedule_refresh(socket) do
    Process.send_after(self(), :refresh, 50)
    assign(socket, :refresh_scheduled, true)
  end

  @spec record_rows([map()]) :: [map()]
  defp record_rows(records) do
    Enum.map(records, fn record ->
      %{
        id: "gam-" <> record.ref,
        kind: record.kind,
        text: inspect(record, pretty: true, limit: 30, printable_limit: 4000)
      }
    end)
  end

  @spec submit(Phoenix.LiveView.Socket.t(), String.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp submit(%{assigns: %{agent: nil}} = socket, _, _), do: socket

  defp submit(socket, text, target) do
    opts =
      case @skills[target] do
        nil -> []
        mount -> [skill: mount]
      end

    case Session.input(socket.assigns.session, text, opts) do
      {:ok, _} -> message(socket, "user", text)
      {:error, reason} -> put_flash(socket, :error, "Input non accettato: #{inspect(reason)}")
    end
  end

  @spec agent_event(Phoenix.LiveView.Socket.t(), atom(), tuple()) :: Phoenix.LiveView.Socket.t()
  defp agent_event(socket, skill, {:response, _, text, _}),
    do: message(socket, to_string(skill), text)

  defp agent_event(socket, skill, {:preview, interaction, generation, chunk}) do
    id = "preview-#{skill}-#{interaction}-#{generation}"
    body = Map.get(socket.assigns.previews, id, "") <> chunk

    socket
    |> assign(:previews, Map.put(socket.assigns.previews, id, body))
    |> stream_insert(
      :messages,
      %{
        id: id,
        source: to_string(skill),
        body: body,
        kind: :preview,
        ref: nil,
        preview_status: :streaming
      },
      limit: -150
    )
  end

  defp agent_event(socket, skill, {:preview_end, interaction, generation, status}) do
    id = "preview-#{skill}-#{interaction}-#{generation}"
    {body, previews} = Map.pop(socket.assigns.previews, id)
    socket = assign(socket, :previews, previews)

    if is_binary(body) do
      stream_insert(
        socket,
        :messages,
        %{
          id: id,
          source: to_string(skill),
          body: body,
          kind: :preview,
          ref: nil,
          preview_status: if(status == :completed, do: :completed, else: :interrupted)
        },
        limit: -150
      )
    else
      socket
    end
  end

  defp agent_event(socket, skill, {:callback_error, _, callback, _}),
    do: message(socket, "system", "Errore #{label(skill)} / #{callback}. Consulta il log locale.")

  defp agent_event(socket, _, _), do: socket

  @spec preview_label(atom()) :: String.t()
  defp preview_label(:streaming), do: "anteprima · proposta in preparazione"
  defp preview_label(:completed), do: "bozza completata · nessuna azione eseguita da questo testo"
  defp preview_label(:interrupted), do: "anteprima interrotta · testo incompleto"

  @spec message(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp message(socket, source, body) do
    id = "message-#{System.unique_integer([:positive, :monotonic])}"

    stream_insert(socket, :messages, %{id: id, source: source, body: body, kind: :text, ref: nil},
      limit: -150
    )
  end

  @spec fixture_url(String.t()) :: String.t()
  defp fixture_url(page),
    do: "http://127.0.0.1:#{DemoSpectreWeb.Endpoint.config(:http)[:port]}/fixtures/#{page}"

  @spec busy?(map(), String.t()) :: boolean()
  defp busy?(skills, target), do: get_in(skills, [@skills[target], :busy]) == true
  @spec label(atom() | String.t()) :: String.t()
  defp label(value),
    do:
      Map.get(
        %{
          "agent" => "Agente",
          "outreach" => "Ricerca",
          "knowledge" => "Memoria",
          "user" => "Tu",
          "gam" => "GAM · richiesta di consenso",
          "system" => "Sistema"
        },
        to_string(value),
        to_string(value)
      )
end
