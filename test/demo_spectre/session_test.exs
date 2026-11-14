defmodule DemoSpectre.SessionTest do
  use ExUnit.Case, async: false
  alias DemoSpectre.{Session, Events}
  alias Spectre.Server

  setup do
    session = start_supervised!({Session, self()})
    info = Session.info(session)
    Phoenix.PubSub.subscribe(DemoSpectre.PubSub, Events.topic(info.id))
    %{session: session, agent: info.agent, id: info.id}
  end

  test "real browser, model stream, Kinetic and two separate GAM consents", c do
    {:ok, _} = Server.input(c.agent, "http://127.0.0.1:4002/fixtures/studio")
    assert_receive {:demo_event, %{kind: :tool, data: %{tool: :lens, result: page}}}, 15_000
    assert is_binary(page)
    assert_receive {:agent_event, {:skill, :outreach, {:preview, _, _, _}}}, 15_000
    pending = shown_pending(c, :outreach)
    assert pending.operation == {{:skill, :outreach}, :kinetic, :send_email}

    refute Enum.any?(
             Events.history(c.id),
             &(&1.kind == :effect and &1.data.class == "demo.email")
           )

    {:ok, status} = Server.input(c.agent, "status")
    assert_receive {:agent_event, {:response, ^status, _, _}}, 3000
    # A second Skill may await its own consent without capturing the first one.
    {:ok, _} = Server.input(c.agent, "ricorda Una seconda richiesta indipendente.")
    other = shown_pending(c, :knowledge)

    assert {:ok, _} =
             Session.decide(c.session, :knowledge, other.presentation.ref, :reject)

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Richiesta chiusa" <> _, _}}},
                   5000

    confirm(c, :outreach, pending)

    assert_receive {:demo_event,
                    %{
                      kind: :effect,
                      data: %{class: "demo.email", result: %{to: "hello@atelier.example"}}
                    }},
                   10_000

    save = shown_pending(c, :outreach)
    assert save.operation == :save_report

    refute Enum.any?(
             Events.history(c.id),
             &(&1.kind == :effect and &1.data.class == "demo.memory")
           )

    confirm(c, :outreach, save)
    assert_receive {:demo_event, %{kind: :effect, data: %{class: "demo.memory"}}}, 10_000

    assert_receive {:agent_event,
                    {:skill, :outreach, {:response, _, "Risultato salvato" <> _, _}}},
                   10_000

    {:ok, _} = Server.input(c.agent, "memoria")
    assert_receive {:agent_event, {:skill, :knowledge, {:response, _, text, _}}}, 10_000
    assert text =~ "hello@atelier.example"
    {:ok, _} = Server.input(c.agent, "diagnostica")

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Diagnostica completata" <> _, _}}},
                   10_000

    {:ok, _} = Server.input(c.agent, "http://127.0.0.1:4002/fixtures/studio")

    assert_receive {:agent_event,
                    {:skill, :outreach,
                     {:response, _, "Questo sito risulta già contattato" <> _, _}}},
                   5000

    assert Enum.count(
             Events.history(c.id),
             &(&1.kind == :effect and &1.data.class == "demo.email")
           ) == 1

    snapshot = Session.snapshot(c.session)
    assert length(snapshot.gam.outcomes) >= 4
    assert Enum.any?(snapshot.gam.evidence, &(inspect(&1) =~ "spectre_skill_invocation"))
    assert snapshot.skills.outreach.pid != snapshot.skills.knowledge.pid

    for tool <- [:lens, :kinetic, :mnemonic, :prism, :beam, :directive, :pulse, :ledger, :lab] do
      assert Enum.any?(Events.history(c.id), &(&1.kind == :tool and &1.data.tool == tool)),
             inspect(tool)
    end
  end

  test "parallel pending requests cannot confirm each other and rejection writes nothing", c do
    {:ok, _} = Server.input(c.agent, "ricorda Solo una nota dimostrativa.")
    pending = shown_pending(c, :knowledge)

    assert {:error, :stale_pending} =
             Server.input(c.agent, "confermo",
               skill: :outreach,
               pending: {pending.id, pending.revision}
             )

    assert {:ok, _} =
             Session.decide(c.session, :knowledge, pending.presentation.ref, :reject)

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Richiesta chiusa" <> _, _}}},
                   5000

    refute Enum.any?(
             Events.history(c.id),
             &(&1.kind == :effect and &1.data.class == "demo.memory")
           )

    assert {:error, :stale_pending} =
             Server.input(c.agent, "confermo",
               skill: :knowledge,
               pending: {pending.id, pending.revision}
             )
  end

  test "a page without email never proposes a send", c do
    {:ok, _} = Server.input(c.agent, "http://127.0.0.1:4002/fixtures/no-email")

    assert_receive {:agent_event,
                    {:skill, :outreach, {:response, _, "La pagina non contiene" <> _, _}}},
                   15_000

    assert Session.snapshot(c.session).gam.acts == []
  end

  test "topic changes close the Skill intention through audited GAM lifecycle", c do
    {:ok, _} = Server.input(c.agent, "ricorda Questa nota non deve essere salvata.")
    pending = shown_pending(c, :knowledge)
    {:ok, _} = Server.input(c.agent, "altro argomento", skill: :knowledge)

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Richiesta chiusa" <> _, _}}},
                   5000

    assert {:error, :stale_pending} =
             Server.input(c.agent, "confermo",
               skill: :knowledge,
               pending: {pending.id, pending.revision}
             )

    snapshot = Session.snapshot(c.session)
    assert Enum.any?(snapshot.gam.evidence, &(inspect(&1) =~ "topic_changed"))
    refute Enum.any?(snapshot.gam.acts, &(&1.class == "demo.memory"))
  end

  test "Beam delivery requires consent and native OTP callbacks remain available", c do
    {:ok, _} = Server.input(c.agent, "notifica")
    pending = shown_pending(c, :knowledge)
    confirm(c, :knowledge, pending)
    assert_receive {:demo_event, %{kind: :effect, data: %{class: "demo.beam"}}}, 5000
    {:ok, skill} = Server.skill_server(c.agent, :knowledge)
    send(skill, :refresh)

    assert_receive {:agent_event,
                    {:skill, :knowledge, {:response, _, "Refresh ricevuto" <> _, _}}},
                   5000
  end

  test "another process cannot acknowledge or approve this UI owner's presentation", c do
    {:ok, _} = Server.input(c.agent, "ricorda Questa nota richiede il proprietario della UI.")
    assert_receive {:presentation, show}, 10_000
    ref = show["presentation_ref"]

    task = Task.async(fn -> Session.presented(c.session, ref) end)
    assert {:error, :unauthorized_transport} = Task.await(task)
    assert :ok = Session.presented(c.session, ref)
    assert_receive {:agent_event, {:skill, :knowledge, {:pending, _, _}}}, 10_000

    task = Task.async(fn -> Session.decide(c.session, :knowledge, ref, :confirm) end)
    assert {:error, :unauthorized_transport} = Task.await(task)
    refute Enum.any?(Events.history(c.id), &(&1.kind == :effect))
    assert {:ok, _} = Session.decide(c.session, :knowledge, ref, :reject)
  end

  test "a custom pending callback can confirm actual input from its UI owner", c do
    assert {:ok, _} = Session.input(c.session, "ricorda Conferma dal callback personalizzato.")
    pending = shown_pending(c, :knowledge)

    assert {:ok, _} =
             Session.input(c.session, "confermo",
               skill: :knowledge,
               pending: {pending.id, pending.revision}
             )

    assert_receive {:agent_event, {:skill, :knowledge, {:response, _, "Nota salvata" <> _, _}}},
                   5000

    assert Enum.count(Events.history(c.id), &(&1.kind == :effect)) == 1
  end

  defp shown_pending(c, skill) do
    assert_receive {:presentation, show}, 15_000
    assert is_binary(show["rendered_payload"])
    Session.presented(c.session, show["presentation_ref"])
    assert_receive {:agent_event, {:skill, ^skill, {:pending, _, id}}}, 15_000
    {:ok, pid} = Server.skill_server(c.agent, skill)
    Enum.find(Server.status(pid).pending, &(&1.id == id))
  end

  defp confirm(c, skill, pending) do
    assert {:ok, _} =
             Session.decide(c.session, skill, pending.presentation.ref, :confirm)
  end
end
