defmodule DemoSpectre.Agent do
  @moduledoc """
  Declares recognition and mounts two independent Skill Server processes.

  Both children automatically reuse the root AgentServer's GAM Domain and
  authority ledger. Each mount keeps local state and pending intentions;
  `governed:` restricts the root operation permissions rather than granting more.
  """
  use Spectre.Agent, stack: DemoSpectre.AI, server: DemoSpectre.AgentServer
  # Deterministic encoder + real Vettore index. Replace the encoder to test semantic quality.
  embedding(DemoSpectre.IntentEmbedding, model: "demo-intents-v1")

  intent_dataset(Spectre.Router.SemanticCache.Learned,
    sources: ["priv/intents/prepared.jsonl"],
    search: [method: :quantized, min_score: 0.95, limit: 2],
    collect: [enabled: false]
  )

  router(strategies: [:regex, :intent_dataset])

  flow :assistant do
    on(:status, regex: ~r/^(status|stato)$/i)
    on(:info, regex: ~r/^(info|aiuto)$/i)
    on(:history, regex: ~r/^(history|cronologia)$/i)
  end

  # The child gets its own Server, but reuses the root's existing GAM connection.
  skill(DemoSpectre.Skills.Outreach,
    as: :outreach,
    governed: [{{:skill, :outreach}, :kinetic, :send_email}, :save_report]
  )

  # Consent for this mount cannot approve Outreach's separate pending requests.
  skill(DemoSpectre.Skills.Knowledge,
    as: :knowledge,
    governed: [
      :save_report,
      :forget_memory,
      :learn_memory,
      :send_notice,
      {{:skill, :knowledge}, :kinetic, :log_hello}
    ]
  )
end
