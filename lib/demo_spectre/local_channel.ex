defmodule DemoSpectre.LocalChannel do
  @moduledoc "Beam transport accepting messages into the demo's local event mailbox."
  @doc "Reports supported content."
  @spec capabilities(keyword()) :: [atom()]
  def capabilities(_opts), do: [:text]
  @doc "Returns a local technical receipt, never an external delivery claim."
  @spec deliver(struct(), keyword()) :: {:ok, struct()}
  def deliver(outbound, _opts),
    do:
      {:ok,
       Spectre.Beam.Receipt.accepted(outbound,
         provider_message_id: "local:" <> outbound.idempotency_key
       )}
end
