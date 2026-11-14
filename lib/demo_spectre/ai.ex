defmodule DemoSpectre.AI do
  @moduledoc "The nine installed packages generate the same helpers in Agent and Skill servers."
  use Spectre.Stack

  install(Spectre.Kinetic,
    mode: :closed_moves,
    actions: DemoSpectre.MailActions,
    modes: [send_email: :write, log_hello: :write]
  )

  install Spectre.Mnemonic,
    automatic: false,
    bind: [remember: :save_report, forget: :forget_memory, learn: :learn_memory] do
    isolate_by([:agent, :subject])
  end

  install Spectre.Lens do
    backend(SpectreLens.Browsers.Lightpanda, instances: 2)
    # This local showcase deliberately visits its own Phoenix fixture page.
    policy(DemoSpectre.BrowserPolicy)
  end

  install Spectre.Prism do
    provider(:demo, DemoSpectre.Model)
    model(:fast, id: "demo-model", supports: [:text, :stream])
    default(:fast)
  end

  install Spectre.Beam, bind: [deliver: :send_notice] do
    channel(:email, adapter: DemoSpectre.LocalChannel)
  end

  install(Spectre.Directive)
  install(Spectre.Pulse)
  install(Spectre.Ledger)
  install(Spectre.Lab)
end
