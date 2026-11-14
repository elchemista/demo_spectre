defmodule DemoSpectre.Test.ModelResultAgent do
  @moduledoc false
  use Spectre.Agent, stack: DemoSpectre.AI, server: DemoSpectre.AgentServer
  router(strategies: [:regex])

  skill(DemoSpectre.Test.ModelResultSkill,
    as: :outreach,
    governed: [{{:skill, :outreach}, :kinetic, :send_email}, :save_report]
  )
end
