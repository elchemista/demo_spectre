defmodule DemoSpectre.ContinuationTest do
  use ExUnit.Case, async: true
  alias DemoSpectre.{Events, Skills.KnowledgeServer, Skills.OutreachServer}
  alias Spectre.Server.{Command, Context}

  setup do
    id = "continuation-#{System.unique_integer([:positive])}"
    on_exit(fn -> Events.forget(id) end)
    %{ctx: %Context{identity: %{subject: id}, assigns: %{job_active: true}}}
  end

  test "unknown successful governed result is reported without crash or repeated action", %{
    ctx: ctx
  } do
    result = {:governed, %{outcome: %{status: :succeeded}, private_payload: "secret"}}
    updated = KnowledgeServer.handle_result(:future_operation, result, ctx)
    assert [%Command{kind: :respond, args: [text]}] = updated.commands
    assert text =~ "continuazione non è riconosciuta"

    assert [%{data: diagnostic}] =
             Enum.filter(Events.history(ctx.identity.subject), &(&1.kind == :diagnostic))

    assert diagnostic.code == :unexpected_success_continuation
    refute inspect(diagnostic) =~ "secret"
  end

  test "multiple contacts stop the outreach chain before model generation", %{ctx: ctx} do
    page = %{url: "https://studio.example", semantic_text: "one@example.com two@example.com"}

    updated =
      OutreachServer.handle_result(:closed, {:ok, %{}}, %{
        ctx
        | assigns: Map.put(ctx.assigns, :page, page)
      })

    assert [%Command{kind: :respond, args: [text]}] = updated.commands
    assert text =~ "2 contatti distinti"
    refute updated.assigns.job_active
  end

  test "a malformed mailto does not leave Outreach permanently active", %{ctx: ctx} do
    page = %{url: "https://studio.example", links: [%{href: "mailto:a%zz@b.com"}]}

    updated =
      OutreachServer.handle_result(:closed, {:ok, %{}}, %{
        ctx
        | assigns: Map.put(ctx.assigns, :page, page)
      })

    assert [%Command{kind: :respond, args: [text]}] = updated.commands
    assert text =~ "non contiene un indirizzo email"
    refute updated.assigns.job_active

    next =
      OutreachServer.handle_flow({:outreach, :new_link}, %{text: page.url}, %{
        updated
        | commands: []
      })

    assert [%Command{kind: :tool}] = next.commands
  end

  test "recipient policy binds observed provenance and rejects model replacement", %{ctx: ctx} do
    contact = %{
      email: "hello@example.com",
      url: "https://studio.example",
      observations: [%{kind: :mailto}]
    }

    ctx = %{ctx | assigns: Map.put(ctx.assigns, :contact, contact)}

    action = %{
      operation: {{:skill, :outreach}, :kinetic, :send_email},
      args: %{"to" => contact.email}
    }

    assert {:confirm, %{bind: %{observed_contact: ^contact}}} =
             OutreachServer.handle_action(action, ctx)

    assert {:reject, :recipient_does_not_match_observed_contact} =
             OutreachServer.handle_action(
               %{action | args: %{"to" => "intruder@example.com"}},
               ctx
             )
  end
end
