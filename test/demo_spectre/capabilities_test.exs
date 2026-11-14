defmodule DemoSpectre.CapabilitiesTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias DemoSpectre.{Session, Events}
  alias Spectre.Server

  setup do
    session = start_supervised!({Session, self()})
    info = Session.info(session)
    Phoenix.PubSub.subscribe(DemoSpectre.PubSub, Events.topic(info.id))
    %{session: session, agent: info.agent, id: info.id}
  end

  test "real Vettore cache chooses exact and vector routes, mounted Skill, and rejects unknown text",
       c do
    assert {:ok, {:assistant, :status}, %{route: %{strategy: :semantic_cache_exact}}} =
             Server.Router.route(DemoSpectre.Agent, "mostrami lo stato")

    assert {:ok, {:assistant, :status}, %{route: %{strategy: :semantic_cache_search}}} =
             Server.Router.route(DemoSpectre.Agent, "come procede il lavoro?")

    assert {:ok, {{{:skill, :knowledge}, :knowledge}, :recall},
            %{route: %{strategy: :semantic_cache_search}}} =
             Server.Router.route(DemoSpectre.Agent, "quali altri ricordi conosci?")

    assert {:unmatched, _} = Server.Router.route(DemoSpectre.Agent, "banana galattica")
    {:ok, _} = Server.input(c.agent, "come procede il lavoro?")
    assert_receive {:agent_event, {:response, _, "Agente disponibile" <> _, _}}, 5000

    assert_receive {:demo_event, %{kind: :routing, data: %{strategy: :semantic_cache_search}}},
                   5000

    {:ok, _} = Server.input(c.agent, "quali altri ricordi conosci?")

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Memoria della sessione" <> _, _}}},
                   5000

    assert {:ok, rows} = Spectre.IntentDataset.examples(DemoSpectre.Agent, source: :all)
    vector_rows = Enum.filter(rows, &(&1.embedding != nil))
    assert length(vector_rows) == 3
    assert Enum.all?(vector_rows, &(length(&1.embedding) == 5))
  end

  test "model-generated Kinetic hello logs only after consent; stale consent does not execute again",
       c do
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: :warning) end)

    before =
      capture_log(fn ->
        {:ok, _} = Server.input(c.agent, "hello")
        pending = shown_pending(c)
        send(self(), {:hello_pending, pending})
      end)

    refute before =~ "[demo.kinetic] hello"
    assert_receive {:hello_pending, pending}
    assert pending.operation == {{:skill, :knowledge}, :kinetic, :log_hello}

    after_consent =
      capture_log(fn ->
        answer(c, pending, "confermo")
        assert_receive {:demo_event, %{kind: :effect, data: %{class: "demo.log"}}}, 5000

        assert_receive {:agent_event,
                        {:skill, :knowledge, {:response, _, "hello scritto" <> _, _}}},
                       5000
      end)

    assert length(Regex.scan(~r/\[demo\.kinetic\] hello/, after_consent)) == 1

    replay =
      capture_log(fn ->
        _ =
          Server.input(c.agent, "confermo",
            skill: :knowledge,
            pending: {pending.id, pending.revision}
          )

        refute_receive {:demo_event, %{kind: :effect, data: %{class: "demo.log"}}}, 200
      end)

    refute replay =~ "[demo.kinetic] hello"

    assert Enum.count(Events.history(c.id), &(&1.kind == :effect and &1.data.class == "demo.log")) ==
             1
  end

  test "cancelled Kinetic hello never reaches Logger", c do
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: :warning) end)

    log =
      capture_log(fn ->
        {:ok, _} = Server.input(c.agent, "hello")
        pending = shown_pending(c)
        answer(c, pending, "annulla")

        assert_receive {:agent_event,
                        {:skill, :knowledge, {:response, _, "Richiesta chiusa" <> _, _}}},
                       5000
      end)

    refute log =~ "[demo.kinetic] hello"
    refute Enum.any?(Events.history(c.id), &(&1.kind == :effect and &1.data.class == "demo.log"))
  end

  test "Mnemonic search, reflection, learning and forget operate through one mounted Skill", c do
    {:ok, _} = Server.input(c.agent, "ricorda Zafferano è il nome del progetto Elixir.")
    pending = shown_pending(c)
    answer(c, pending, "confermo")

    assert_receive {:agent_event, {:skill, :knowledge, {:response, _, "Nota salvata" <> _, _}}},
                   5000

    {:ok, _} = Server.input(c.agent, "cerca Zafferano")
    assert_receive {:demo_event, %{kind: :memory_results, data: %{results: results}}}, 5000
    record = Enum.find(results, &(&1.record.text == "Zafferano è il nome del progetto Elixir."))
    assert record

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Risultati della ricerca" <> _, _}}},
                   5000

    {:ok, _} = Server.input(c.agent, "rifletti Zafferano")

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Contesto con fonti" <> _, _}}},
                   5000

    {:ok, _} = Server.input(c.agent, "mappa memoria")

    assert_receive {:agent_event, {:skill, :knowledge, {:response, _, "Mappa memoria" <> _, _}}},
                   5000

    {:ok, _} = Server.input(c.agent, "impara Rilascio\n- Esegui i test\n- Controlla i processi")
    answer(c, shown_pending(c), "confermo")

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Conoscenza salvata" <> _, _}}},
                   5000

    {:ok, _} = Server.input(c.agent, "conoscenze")
    assert_receive {:agent_event, {:skill, :knowledge, {:response, _, knowledge, _}}}, 5000
    assert knowledge =~ "Esegui i test"
    {:ok, _} = Server.input(c.agent, "dimentica " <> record.id)
    pending = shown_pending(c)
    assert pending.operation == :forget_memory
    answer(c, pending, "confermo")

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Ricordo dimenticato" <> _, _}}},
                   5000

    {:ok, _} = Server.input(c.agent, "cerca Zafferano")
    assert_receive {:demo_event, %{kind: :memory_results, data: %{results: after_forget}}}, 5000
    refute Enum.any?(after_forget, &(&1.id == record.id))
    assert Enum.any?(Session.snapshot(c.session).gam.acts, &(&1.class == "demo.forget"))
  end

  defp shown_pending(c) do
    assert_receive {:presentation, show}, 10_000
    Session.presented(c.session, show["presentation_ref"])
    assert_receive {:agent_event, {:skill, :knowledge, {:pending, _, id}}}, 10_000
    {:ok, pid} = Server.skill_server(c.agent, :knowledge)
    Enum.find(Server.status(pid).pending, &(&1.id == id))
  end

  defp answer(c, pending, text) do
    assert {:ok, _} =
             Session.decide(
               c.session,
               :knowledge,
               pending.presentation.ref,
               if(text == "confermo", do: :confirm, else: :reject)
             )
  end
end
