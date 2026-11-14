defmodule DemoSpectre.Test.ModelResultSkill do
  @moduledoc false
  use Spectre.Skill, id: :outreach, server: DemoSpectre.Test.ModelResultServer

  flow :model do
    on(:response, regex: ~r/\A[\s\S]+\z/, collect_intent: false)
  end
end
