defmodule DemoSpectre.Skills.Knowledge do
  @moduledoc "Memory and tool diagnostics, independent of the outreach conversation."
  use Spectre.Skill, id: :knowledge, server: DemoSpectre.Skills.KnowledgeServer

  flow :knowledge do
    on(:recall,
      regex: ~r/\Amemoria(?:\s+.+)?\z/is,
      semantic_examples: ["chi abbiamo contattato?"]
    )

    on(:search, regex: ~r/^cerca\s+.+/i, collect_intent: false)
    on(:reflect, regex: ~r/^rifletti\s+.+/i, collect_intent: false)
    on(:atlas, regex: ~r/^mappa memoria$/i)
    on(:knowledge, regex: ~r/^conoscenze$/i)
    on(:learn, regex: ~r/^impara\s+.+/is, collect_intent: false, protected: true)
    on(:forget, regex: ~r/^dimentica\s+\S+$/i, collect_intent: false, protected: true)
    on(:log_hello, regex: ~r/^hello$/i, collect_intent: false, protected: true)
    on(:remember, regex: ~r/^ricorda\s+.+/i, collect_intent: false, protected: true)
    on(:diagnostics, regex: ~r/^diagnostica$/i)
    on(:notice, regex: ~r/^notifica$/i, protected: true)
    on(:resume, regex: ~r/^riprendi memoria$/i)
  end
end
