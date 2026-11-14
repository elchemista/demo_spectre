# Verification and adversarial checks — 2026-11-14

## Opus review follow-up

After the review fixes, the final demo passed **41/41** `mix precommit` tests
(44.6 seconds), including the Git-pin consistency check. The four relevant
Chromium scenarios passed again (**4/4**, 23.3 seconds): all nine packages,
eight concurrent status requests with Beam/Outreach, mobile layout, and reconnect
with stale consent rejection. Both runs used Lightpanda 1.0.4. The earlier full
20-scenario run remains recorded below. The endpoint was stopped and port 4000
verified closed after the browser run.

The added regressions verify malformed percent-encoding in mailto links is
ignored and Outreach accepts the next request; a Skill disappearing between
lookup and status cannot terminate Session; root diagnostic read exits become
errors; and a real Agent read timeout preserves the LiveView's session and last
snapshot, shows a retry control, and recovers to a working chat. Actual monitored
Session death still disconnects the page. Duplicate redacted records with no
reference retain distinct display IDs across pages using an ordinal plus digest.

On the tested Elixir version, malformed `%zz` was preserved by `URI.decode/1`
rather than raising. The parser therefore rejects malformed percent escapes
explicitly and also catches `ArgumentError` from decoding. A failed diagnostic
subscription retries; transient inspection errors never act as session shutdown.

Logs: `/tmp/demo-opus-final-precommit.log`, `/tmp/demo-opus-fixes-browser.log`,
`/tmp/demo-opus-fixes-server.log`. The synthetic ID regression also passed in
`/tmp/demo-opus-record-ids-final.log`. The final server log has no application
warnings or errors. The nil-reference display adjustment followed the browser
run and is covered by the final full ExUnit run.


## 0.4 release preparation: diagnostics and demo hardening

The final source passed **36/36** `mix precommit` checks (37.7 seconds) and
**20/20** Chromium scenarios (3.2 minutes), using the official **Lightpanda 1.0.4**
binary also pinned by CI. The browser endpoint was stopped after verification;
no development webserver is left running.

The new regressions cover structured Lens contacts, ignored metadata and mailto
query recipients, source provenance, ambiguous contacts stopping before model
generation, recipient substitution rejection, and unknown successful
continuations reporting diagnostics without retrying an effect. LiveView tests
exercise more than 50 GAM records, pagination, revision reset, payload redaction
and owner-only Session inspection. The browser exercises all nine packages,
both Skill processes, separate confirmations, timer expiry, reconnection,
semantic routing, Kinetic hello, and Mnemonic search/reflection/forget/knowledge.

The inspector now reads safe paginated GAM records and Lab operational metadata
for root and Skill checkpoints. Notifications drive coalesced refreshes; the
full ledger is no longer polled. The operational panel has bounded internal
scrolling, verified in the [desktop capture](screenshots/desktop.png), and the
mobile browser scenario checks horizontal overflow. The diagnostic Skill flow
also uses Lab's `{:inspect, :checkpoint, :operational}` helper.

One old stress-test assertion depended on how many repeated button clicks
LiveView delivered while that button was loading. It now submits eight actual
websocket events and verifies all eight accepted inputs receive eight responses,
while Beam and Outreach remain responsive. The complete final browser run
passed with this stronger deterministic assertion. No application warning or
error was found in the final server log.

Commands used the local sibling override while testing the exact coordinated
source: `SPECTRE_LOCAL_DEPS=1 LIGHTPANDA_PATH=/tmp/spectre-lightpanda-1.0.4`.
Public commit pinning and clean-clone reproduction are separately described in
the README; these results do not claim live LLM, external SMTP or public browsing.
The fixture-only browser policy remains in place.

Local logs: `/tmp/demo-release-ready-precommit.log`,
`/tmp/demo-release-ready-browser.log`, `/tmp/demo-release-ready-server.log`.
The earlier entries below are historical baselines, not the current server state.


The showcase is tested in a real headless **Chromium** browser through Playwright,
with JavaScript, LiveView hooks and WebSockets enabled. Lens uses a separate real
Lightpanda browser to read the local fixture. No remote email is sent.

## Reproduce

Start the deterministic application with `mix phx.server`, then run:

```sh
npm ci
npx playwright install chromium ffmpeg
npm run test:browser
mix precommit
```

`test/browser/adversarial.spec.cjs` contains the browser scenarios. ExUnit uses
port 4002 and a temporary data root; Playwright uses the running dev endpoint on
4000 and disposable chat identities. Avoid editing watched application files
while running browser tests because Phoenix live reload replaces the session.

## Browser results

The final release run passed **all 20 Chromium scenarios in one clean run**
(3.9 minutes), including memory operations, vector-cache routing and the governed
Logger action. The application was restarted after the last framework and package
changes. No server errors or warnings were observed during that run.
The memory scenario was then rechecked with stronger assertions: no pending
request remains after confirmed forgetting, and the screenshot waits for the
new search response rather than matching an older message. That focused rerun
also passed; no application change was needed.

Desktop/mobile workflow, memory results and the managed consent material were
visually inspected. The pending card shows the actual frozen material beside the
confirm/reject controls. Values are quoted and multiline/control characters are
escaped so content cannot impersonate another field or hide its boundaries.
Screenshots: [desktop](screenshots/desktop.png), [mobile](screenshots/mobile.png),
[memory](screenshots/memory.png), [consent](screenshots/managed-consent.png) and
[mobile consent](screenshots/managed-consent-mobile.png).

## Managed GAM migration

The demo now uses Spectre's managed GAM configuration. `DemoSpectre.Host`,
`Host.Ingress`, `Host.Mind` and `Host.Executor` have been removed. Session code
configures allowed operations and relays its UI owner's actual input; the
framework provisions the mediated boundary and records the protocol.
Business checks remain in ordinary Skill Server `handle_action/2` callbacks.
The authority ledger and coordination checkpoints both use local disk storage;
this avoids claiming durable coordination over a volatile authority record.

The final `mix precommit` run passed **27 tests**, including two new checks:

- another process cannot acknowledge or approve the UI owner's presentation;
- the custom `handle_pending` callback can accept actual owner input, while
  using the same governed path as the structured confirmation button.

The UI decision includes the presentation reference and is checked against the
Skill, pending ID and revision. Rendering acknowledgement is separate from
approval. Receipt panels are projected from actual successful recorded outcomes,
not from an executor-side application hook. The application keeps no Scope or
submission credential in tool/model context.

The first migration runs exposed issues corrected in Spectre: a missing frozen
material field in the consequence contract, normalization of the internal journal
store result and a journal-release/shutdown race. A browser assertion also assumed
the old custom presentation's exact whitespace; it now verifies the selected
record in the exact pending card's material. The final runs above pass after those
changes, with no shutdown exception. Test launch was also sequenced after the dev
endpoint was ready to avoid connection-refused errors during compilation.

The implementation review additionally led to these verified corrections:

- mismatched Skill/root targets are validated before authorizing a consent receipt;
- relays use bounded calls and return explicit errors if a Skill stops or stays busy;
- custom binding callbacks receive sanitized context, with mandatory frozen material preserved;
- actual nonliteral user replies can be interpreted by a custom binding without exposing transport receipts;
- ephemeral authority storage cannot be combined with independently persistent coordination state.

A separate core regression file checks six cases around decision targets, busy/killed
Skill relays and forged relay tokens. The demo uses matching disk durability for
GAM authority history and its external coordination checkpoint. Final browser and
ExUnit runs above were repeated after all review corrections, without server errors.

## Browser scenarios

| Scenario | Required outcome |
| --- | --- |
| Complete Lens → stream → Kinetic → email → Mnemonic | Two distinct confirmations; memory readback; one email; all nine tool badges exercised |
| Ambiguous, negative and instruction-injection replies | No inferred approval; suspend/re-present or explicit refusal |
| Two Skill requests at once | Confirmation cannot cross Skill or pending identity |
| Repeated clicks and old-event replay | One email; no accidental approval of the following save |
| Suspend and resume | Fresh revision; old button rejected; old timer cancelled after the real 30-second boundary |
| Let an intent expire | Audited closure; stale button rejected; no write |
| Two notes in the same Skill | Each retains its original payload; one can be saved while the other is rejected |
| Unknown events and malformed parameter types | LiveView stays alive with the same Domain |
| Empty/large Unicode/HTML input | Bounded input; escaped HTML; no script execution |
| External/metadata/userinfo/query URLs | Reject navigation, then recover for a valid page without email |
| Rapid root requests while both Skills work | Every accepted root request receives its response; Beam still requires consent |
| Two tabs and page reload | Memory, effects and authority isolated; old approval cannot cross or survive sessions |
| 390px mobile viewport | No horizontal overflow; real confirmation and rejection controls work |
| Lost rendering ack and late ack | No usable consent; uncertain presentation recorded; late ack cannot authorize a write |
| WebSocket disconnect/reconnect | New session authority; previous confirmation rejected |
| IntentDataset exact/vector paths | Actual cache strategy visible, mounted Skill dispatch, unknown fallback, regex precedence |
| Kinetic hello with click/replay | Real Logger effect only after consent; duplicate/stale event creates no second receipt |
| Kinetic hello cancellation | No Logger effect or receipt |
| Mnemonic query/reflect/forget | Source-backed results, separate forget consent, cancellation preserves result, confirmation hides selected record |
| Mnemonic empty/malformed/learn | Empty query results, forged filters/IDs rejected, reusable knowledge saved only after consent |

The browser suite saves desktop/mobile screenshots and retains failure traces,
video and screenshots. These are generated in ignored directories. The HTML
report of the latest invocation is `playwright-report/index.html`.
Inspected screenshots: [desktop](screenshots/desktop.png), [mobile](screenshots/mobile.png), and [memory](screenshots/memory.png).

## Defects found and corrected

1. **Lens leaked browser processes at supervisor shutdown.** Runtime startup
   deliberately linked only after successful allocation, so it was not a normal
   OTP parent link. The catch-all swallowed the supervisor's shutdown signal;
   forced termination skipped cleanup. Lens now tracks and monitors its owner
   and handles its exit explicitly. A regression failed with `:killed` before
   the change. Fake-backend tests and a real two-Lightpanda shutdown test now
   verify cleanup; after closing the browser suite, no Lightpanda process is left.
2. **Malformed client events crashed LiveView and silently created a new chat.**
   Unknown targets/events and invalid text/revision types are rejected without
   replacing the session. Browser tests retain and compare the actual Domain ID.
3. **A queued refresh could crash after session termination.** The view now
   becomes a stable disconnected page, clears pending controls, and stops polling
   instead of calling a dead/nil process or reading an empty GAM projection.
4. **Preview completion left stale UI and reset other streams.** Terminal events
   now update only their own preview, mark completion/interruption explicitly,
   and retain other active stream buffers. Regression tests interleave two streams.
5. **Fixed memory search missed unrelated saved notes.** `memoria <terms>` now
   passes an explicit cue to Mnemonic; empty results explain how to search.
   The default contact query is not presented as a complete inventory.
6. **The GAM inspector hid lifecycle details.** Bounded raw inspection consumed
   its budget on identity bindings. It now shows the recorded lifecycle event
   first, including the actual reason for suspension/closure.
7. **Fixture navigation accepted URL variants outside the documented allowlist.**
   Queries, fragments and userinfo are now excluded in addition to scheme,
   host, port and path checks. Valid browsing remains available after refusal.

8. **Long desktop conversations pushed the composer out of view.** Visual
   inspection found the grid's automatic minimum height expanding with chat
   content. The chat panel now permits a bounded height and internal scrolling.
   The browser checks that the composer remains inside the viewport after the
   full workflow, and separately checks mobile overflow and consent controls.

9. **The Mnemonic Server adapter exposed only recall and remember.** Its explicit
   catalogue now includes nine reads and thirteen host-bound writes. Operation
   options are validated inside the request tuple; identity/runtime/adapter
   overrides are rejected. The existing core helper needs no additional DSL.
10. **Read retries could reinforce memory.** Explicit read helpers now disable
    attention/graph reinforcement, reclustering and secret reveal. Tests compare
    persistence before/after reads and check cross-subject isolation.
11. **Compact knowledge lost a named engine's namespace.** The default compactor
    normalized existing events without their engine options. It now preserves
    those options during summary construction and event retention.
12. **Approximate cache evidence could replace a literal command in the new
    Server.** Server routing now uses hard regex evidence by default, preserving
    explicit weaker overrides. An initial broader fix failed the 0.3 strategy
    matrix; it was narrowed to the new Server so legacy precedence is unchanged.
13. **Skill Server prompt roots were ignored.** Overrides now carry their own
    runtime scope. A root Server cannot replace another Skill's prompt assets;
    the Skill Server's own root works and path containment remains enforced.
14. **The composer retained sent text.** A draft event now keeps the form state
    synchronized, so accepted input clears reliably. Invalid input remains
    editable. Forget confirmation now displays the selected record text rather
    than only an opaque ID; its text and subject are frozen into the consequence.

Two initial browser assertions were also corrected: the expected root fallback
wording and an assumption that every rapid duplicate DOM click is accepted by
LiveView. The latter now compares responses with the number of accepted inputs.
Those were test assumptions, not GAM defects.

## Provider-result adversarial tests

Six ExUnit cases inject a consolidated response at the model-result boundary
and then run the real Skill/Kinetic/managed-GAM path: changed recipient, unknown
operation, a plain claim that sending already succeeded, missing arguments,
incomplete AL, and multiple actions. Each verifies no effect and then submits
and rejects a fresh valid proposal to check recovery. No live model or fabricated
approval is used.

## Previous full framework/package baseline

- Core full suite before the automatic-boundary completion: **4,442 passed** (1 doctest, 25 properties, 4,416 tests),
  **1 excluded**. This includes legacy strategy compatibility, cache/training,
  mounted Skills, GAM, managed integration and runtime regressions.
- Demo `mix precommit`: **27 passed**, warnings-as-errors compilation and format pass.
- Browser release run: **20 passed**, with real Chromium, LiveView hooks,
  WebSockets and Lens/Lightpanda.
- Kinetic full suite: **1,339 passed**.
- Mnemonic full suite: **538 passed, 11 real-embedding tests excluded**.
- Beam full suite: **199 passed**; Pulse full suite: **189 passed**.
- Lens full suite: **184 passed, 20 integration tests excluded**. The demo browser
  run additionally exercises actual Lightpanda resource creation and cleanup.
- All nine installable packages compile with warnings as errors.
- Core ExDoc builds with warnings as errors; format checks pass.

The framework/package counts above are the prior coordinated baseline. The
automatic-boundary completion is checked separately below; do not treat the old
core total as a rerun of the new API. This demo owns the 27 ExUnit and 20 Chromium
scenarios described here.

The earlier named-engine Mnemonic regression remains fixed: record reinforcement
resolves the owning namespace/engine, and plasticity propagates update errors
rather than crashing on `:mnemonic_busy`.

## Limits

These tests cover the deterministic demo's declared flows and representative
operations of all nine packages, not every package API. OpenRouter/live keys,
external SMTP, remote Pulse transports, neural embedding quality and
account-backed session recovery are not exercised. Core tests cover offline
embedding preparation, classifier companion artifacts, online collection,
verification and re-embedding; the demo uses a deterministic encoder with the
real Vettore index. Shared intent collection is disabled in the demo. The GAM
ledger and coordination checkpoint now both use session-specific disk storage;
each reconnect still receives a new identity. The UI does not automatically
resume an old session or implement account login. Other browser engines and
physical mobile devices were not tested. No claim is made that testing proves
all possible failures absent. No commit, push or merge was performed.

## Final review resolution

Opus 5.5 reviewed the implemented source. Its confirmed findings were corrected
and covered with regressions: callback context privacy, consent material integrity,
proof target validation/retry, bounded Skill relay failure, frozen policy, coherent
durability and restored consent. The claimed nil-override bypass was not reproducible
because callback validation already rejected nil; it received an explicit regression.
See the core review resolution under docs/proposals/reviews.

Previous core baseline: /tmp/spectre-managed-final-all-green.log, 4442 passed. A pre-existing
real-time test had a one-second setup budget under concurrent load; its margin was
increased while preserving the original-deadline and restart assertions. The final
full suite passed after that test correction. The final browser suite passed 20/20
on the disk-backed configuration, plus a focused memory recheck requiring fresh
results and no stale pending controls.

## Automatic-boundary completion

The demo no longer supplies `authority: :development`. AgentServer uses the same
automatic GAM integration for every environment, with a mediated host boundary,
explicit allowed operations and coherent disk history. Application code retains
business checks and UI authentication; it creates no Scope or ingress.

The updated demo `mix precommit` passed **27/27** on this configuration
(`/tmp/demo-automatic-gam-precommit.log`). The matching full Chromium run passed
**20/20 in 3.3 minutes** (`/tmp/demo-automatic-gam-browser.log`), including all nine
packages, parallel Skills, consent/replay/expiry, semantic-cache routing and
Mnemonic search/reflection/forgetting/knowledge. No server errors or warnings
were observed. All nine satellite ExDoc builds also passed with warnings as errors
(`/tmp/spectre_<package>-automatic-gam-docs.log`). This full browser run preceded
the final capability-broker changes; their fresh-server verification is recorded
separately. Prior framework totals above describe the earlier baseline.

After the capability broker and final automatic-boundary changes, the application
was stopped and rebuilt from source. `mix precommit` again passed **27/27**
(`/tmp/demo-automatic-gam-final-precommit.log`, 47.2 seconds). A fresh-server
Chromium run passed **6/6** focused scenarios in 55.6 seconds
(`/tmp/demo-automatic-gam-final-browser.log`): the full nine-package workflow,
parallel Skill consent isolation, Kinetic hello confirm/replay/cancel, and both
Mnemonic search/reflection/forgetting/knowledge scenarios. The server log
(`/tmp/demo-automatic-gam-final-server.log`) contains no errors or warnings.

After optional independent Duty review was added to the framework, the demo was
rebuilt and restarted once more. Its default configuration intentionally has no
reviewer. The all-nine-package Chromium workflow passed again (**1/1**, 9.2 seconds)
with real Lens, both Skills, separate email/memory consent and native Skill messages
(`/tmp/demo-automatic-gam-ready-browser.log`). The running endpoint on port 4000
uses that revision; `/tmp/demo-automatic-gam-ready-server.log` has no warnings or
errors. Independent Duty disposition itself is covered by the core tests, not
claimed as a demo UI feature.

Final delivery source, after the record-view access and consent-text proof fixes:
**27/27** `mix precommit` (31.0 seconds) and a fresh-server **1/1** all-nine-package
Chromium smoke (10.9 seconds). Logs: `/tmp/demo-automatic-gam-delivery-precommit.log`,
`/tmp/demo-automatic-gam-delivery-browser.log` and the clean running-server log
`/tmp/demo-automatic-gam-delivery-server.log`. The endpoint remains on port 4000.

## Shared-GAM documentation follow-up

The README, source module documentation and [shared-GAM walkthrough](SHARED_GAM.md)
now explain the root's one automatic connection, the shared Domain/authority
ledger, per-Skill state and checkpoints, mount operation restrictions, invocation
provenance, isolated consent and recorded lifecycle timers. Core and all nine
companion package READMEs and integration/migration guides use the same contract.
Stale instructions to implement Skill ingress and the deleted Host fixture link
have been corrected.

Checks after this documentation update, 14 November 2026:

- `mix docs --warnings-as-errors`: core and **9/9** companion packages passed.
- `mix precommit`: **27/27** demo tests, 29.5 seconds.
- Chromium: **2/2**, 16.7 seconds: the all-nine-package workflow and parallel
  Skill confirmations with stale cross-Skill input rejection.
- Documentation consistency, new local file links and `git diff --check` passed.

Logs: `/tmp/spectre-shared-skills-docs.log`,
`/tmp/spectre_*-shared-skills-docs.log`,
`/tmp/demo-shared-skills-precommit.log` and
`/tmp/demo-shared-skills-browser.log`. The server was restarted from this source,
returned HTTP 200 on port 4000 and logged no application errors or warnings
(`/tmp/demo-shared-skills-server.log`). The model and mailbox remain deterministic
and local; these checks do not claim remote provider or SMTP validation.
