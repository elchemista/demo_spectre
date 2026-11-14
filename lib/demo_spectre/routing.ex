defmodule DemoSpectre.Routing do
  @moduledoc "Publishes the actual router evidence to the demo inspector."
  @doc "Records which strategy selected this callback."
  @spec record(Spectre.Server.Context.t()) :: :ok
  def record(ctx) do
    route = ctx.routing[:route]

    DemoSpectre.Events.publish(ctx.identity.subject, :routing, %{
      strategy: route && route.strategy,
      label: route && route.label,
      confidence: route && route.confidence
    })

    :ok
  end
end
