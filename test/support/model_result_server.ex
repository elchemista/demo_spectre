defmodule DemoSpectre.Test.ModelResultServer do
  @moduledoc false
  use Spectre.Server, tools: DemoSpectre.AI
  alias DemoSpectre.Skills.OutreachServer

  # Inject at the provider result boundary, keeping the real Kinetic tool,
  # scoped Skill permissions, registered bindings and GAM admission afterwards.
  @impl true
  def handle_flow(_, input, ctx) do
    ctx =
      ctx
      |> assign(:email, "hello@atelier.example")
      |> assign(:url, "http://127.0.0.1:4002/fixtures/studio")
      |> assign(:job_active, true)

    OutreachServer.handle_result(
      :model,
      {:generated, %{text: input.text, model_output: input.text, planning: false}},
      ctx
    )
  end

  @impl true
  def handle_action(action, ctx), do: OutreachServer.handle_action(action, ctx)

  @impl true
  def handle_result(tag, result, ctx), do: OutreachServer.handle_result(tag, result, ctx)
  @impl true
  def handle_pending(pending, input, ctx), do: DemoSpectre.Pending.handle(pending, input, ctx)
end
