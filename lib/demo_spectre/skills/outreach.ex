defmodule DemoSpectre.Skills.Outreach do
  @moduledoc "Reusable research/contact routes, independently supervised when mounted."
  use Spectre.Skill,
    id: :outreach,
    server: DemoSpectre.Skills.OutreachServer,
    prompt_root: "priv/prompts"

  flow :outreach do
    # Recognition is cognitive. No email authority is acquired by matching a URL.
    on(:new_link, regex: ~r/^https?:\/\/\S+$/i, collect_intent: false, protected: true)
    on(:status, regex: ~r/^stato ricerca$/i, dataset_lookup: false)
    on(:resume, regex: ~r/^riprendi ricerca$/i, dataset_lookup: false)
  end
end
