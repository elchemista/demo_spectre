# Two Skill servers, one automatic GAM

This demo already uses the Spectre 0.4 automatic integration. The Agent owns the
conversation entry point; Research and Knowledge each run ordinary Server
callbacks in a separate GenServer. Spectre connects them to the root's existing
GAM boundary and its separate Domain process.

```text
LiveView → Session (configured consumer and UI relay)
              │
              └── AgentServer ────────────┐
                    ├── OutreachServer ──┼──→ automatic Server.GAM
                    └── KnowledgeServer ─┘           │
                                                    ↓
                                          one Domain / authority ledger
                                                    │
                                          admission → Act → adapter → Outcome
```

There is no `DemoSpectre.Host`, Domain per Skill, copied ledger or manually
implemented Skill ingress. Mounting a Skill creates no additional grant.

## What is shared and what stays local

| Shared within the chat | Local to each Agent/Skill Server |
| --- | --- |
| GAM Domain, authority ledger and automatic execution boundary | GenServer mailbox, callbacks and assigns |
| Authenticated session identity and root operation configuration | Workers, result continuations and streams |
| Evidence, Decisions, Acts, Outcomes and Duties | Pending intentions and exact presentation correlation |
| Installed Stack and supervised browser/memory resources | Coordination checkpoint under its own key |

The shared kernel orders admission. Separate processes allow cognition and
workers to progress concurrently; concurrency does not authorize effects or
override the kernel's rules. Skill invocation Evidence identifies the mount,
module, interaction and command responsible for each proposal.

## Follow the actual source

1. [ai.ex](../lib/demo_spectre/ai.ex) installs the nine packages once. The generated
   helpers are available in both Skill Server callback modules selecting this
   Stack; resources remain in the supervised Stack runtime.
2. [agent.ex](../lib/demo_spectre/agent.ex) declares root flows and mounts
   `:outreach` and `:knowledge`. Each `governed:` list restricts the operations
   that mount may propose. For example, only Outreach lists its scoped
   `{{:skill, :outreach}, :kinetic, :send_email}` operation.
3. [session.ex](../lib/demo_spectre/session.ex) starts the root once with session
   identity, disk storage, operation configuration and `consumer: self()`.
   Spectre creates GAM and passes its existing connection to the children. This
   module relays authenticated UI input and events; it implements no GAM kernel.
4. [outreach_server.ex](../lib/demo_spectre/skills/outreach_server.ex) uses Lens,
   the completed model result and Kinetic to propose an email. Its business
   callback checks the recipient against the observed page. GAM handles the
   presentation, consent, admission, Act, execution and Outcome.
5. [knowledge_server.ex](../lib/demo_spectre/skills/knowledge_server.ex) uses the
   same installed tools for memory and diagnostics. Its state, pending requests
   and native `handle_info` remain independent of Outreach's Server.
6. [chat_live.ex](../lib/demo_spectre_web/live/chat_live.ex) renders each exact
   Presentation and acknowledges rendering separately from approval. Its
   decision is relayed through Session to
   `Spectre.Server.decide(agent, skill, presentation_ref, decision)`. The
   framework checks the originating mount and presentation; model text is not
   treated as user consent.

The root `gam:` operations and the mount's `governed:` references must both
permit an effect. Installed capabilities alone grant no authority. Application
callbacks can add business restrictions; they cannot create consent, widen
authority or replace kernel admission.

## Try two pending Skills

1. Choose **Apri sito di esempio**. Wait for Research's email confirmation.
2. Leave it open and choose **Salva nota**. Knowledge can prepare its own memory
   request while Research is waiting.
3. Open **Identità e processi**: Research and Knowledge have different PIDs under
   the same Domain. Root `status` remains available.
4. Confirm Research's email only. Knowledge's note still requires its own
   decision. Research's subsequent save request also requires separate approval.
5. Reject Knowledge's note. This does not reject another pending request or
   undo the email already executed.
6. Inspect **Registro GAM**. It is the shared projection of Evidence, Decisions,
   Acts, Outcomes and Duties, not a merge of independent Skill audit logs.

Replayed, mismatched or stale controls cannot approve another request. An
untargeted “yes” never guesses which Skill to approve. Rendering acknowledgement
alone is not approval, and admission alone is not proof of successful execution;
the observed Outcome supplies that fact.

## Timers and recovery

**Sospendi** changes topic within Research and schedules an audited closure after
30 seconds. That Skill owns the pending intention; the shared Domain records
its lifecycle transition. **Riprendi** before expiry creates a fresh
Presentation. An old confirmation cannot approve that new revision.

Closing an intention or stopping a Skill does not erase a committed Act,
ambiguous Outcome or unresolved Duty. Child checkpoints preserve local
continuations under separate keys, while the authority history and command
journal keep their coherent shared storage. A new browser session in this demo
starts a new identity and Domain; automatic reattachment to an old chat is not
part of this showcase.

## Verification

The Chromium suite exercises simultaneous Skill requests, isolated confirmation,
stale controls and real expiry timers. The all-nine-package workflow uses both
Skills and the real shared GAM, with a deterministic model and local mailbox.
The core's all-tools Skill integration also asserts email/save Acts and Skill
invocation Evidence through the root's single GAM projection.

See [verification results](VERIFICATION.md), the [core Skill contract](../../spectre/docs/SKILLS.md)
and the [GAM manifesto](https://spectre.guide/en/governed-act-model).
