defmodule DemoSpectre.Pending do
  @moduledoc "Ordinary application policy shared by the two Servers; all transitions use GAM commands."
  import Spectre.Server
  @doc "Accepts explicit answers or suspends the intent while handling another topic."
  @spec handle(map(), Spectre.Input.t(), Spectre.Server.Context.t()) :: Spectre.Server.Context.t()
  def handle(pending, input, ctx) do
    case String.downcase(String.trim(input.text)) do
      value when value in ["confermo", "si", "sì"] ->
        confirm_pending(ctx, pending.id)

      value when value in ["annulla", "no"] ->
        reject_pending(ctx, pending.id)

      _ ->
        ctx
        |> close_pending_after(
          pending.id,
          Application.get_env(:demo_spectre, :pending_timeout_ms, 30_000),
          reason: :topic_changed
        )
        |> route_current_input(suspend: pending.id)
    end
  end

  @doc "Re-presents a suspended intention before accepting a fresh confirmation."
  @spec resume(Spectre.Server.Context.t()) :: Spectre.Server.Context.t()
  def resume(ctx) do
    case Enum.find_value(ctx.pending_by_id, fn {_, p} -> if p.status == :suspended, do: p end) do
      nil -> respond(ctx, "Non ci sono richieste sospese.")
      pending -> resume_pending(ctx, pending.id)
    end
  end
end
