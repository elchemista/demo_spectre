defmodule DemoSpectre.Knowledge.Diagnostics do
  @moduledoc "Diagnostic and notification presentation, separate from memory behavior."

  @doc "Handles diagnostic effects and safely reports an unknown successful continuation."
  @spec success(term(), Spectre.Server.Context.t()) :: String.t()
  def success(:hello_logged, _ctx), do: "hello scritto nel log dopo conferma."
  def success(:notified, _ctx), do: "Notifica Beam accettata nella casella locale."

  def success(tag, ctx) do
    DemoSpectre.Events.publish(ctx.identity.subject, :diagnostic, %{
      skill: :knowledge,
      code: :unexpected_success_continuation,
      continuation: inspect(tag, limit: 3, printable_limit: 80)
    })

    "GAM ha registrato un risultato riuscito, ma la continuazione non è riconosciuta. Nessuna operazione ripetuta; controlla la diagnostica."
  end
end
