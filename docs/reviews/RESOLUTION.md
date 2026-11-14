# Release review resolution — Spectre 0.4

The implementation was reviewed twice by Claude Opus 5.5, with the architecture,
GAM invariants, source locations and test evidence provided in the saved briefs.
The [first review](opus-5.5-release-review.md) identified one blocker and several
medium issues. The [follow-up](opus-5.5-followup.md) found no remaining concrete
blocker in the corrected code. Both reviews were read-only; the reviewer did not
run the tests. Model identity and invocation metadata are saved alongside them.

## Changes made after review

| Finding | Resolution and regression |
| --- | --- |
| B1: diagnostic timeout could terminate Managed and its Domain | Bounded, monitored internal read workers handle both paginated diagnostics and the legacy view. Query timeout is 3.5s, watchdog 4s, maximum four readers. Authorization precedes dispatch; readers are separate from governed workers and shutdown draining. A suspended Domain does not stop Managed checkout or the Agent. |
| M1: initial subscription failure left checkpoint notifications disabled | Subscription accepts the intent while the disposable notification process is unavailable. Retry, rejoin and authoritative head refresh restore delivery. |
| M2: a slow restarting Skill lost its subscription | An authenticated reserved parent message is processed after child initialization. The root does not synchronously wait for the child; forged tokens are ignored. |
| M3: custom-adapter trace discarded an available checkpoint | Internal custom runtimes return the retained trace with `gam: nil` and explicit unavailable coverage. Public AgentServers continue using automatic managed GAM. |
| M4: malformed mailto | Invalid percent encoding is rejected, with a defensive decode rescue. On the tested Elixir version `%zz` was preserved rather than raising: the concrete issue was accepting malformed URI text as an email local part. Tests cover both malformed candidates and recovery of the workflow. |
| M5: temporary diagnostics disconnected the chat | Session catches read exits; LiveView keeps its last snapshot, pending controls and session, with a retryable warning. Only actual Session death disconnects. Dead-Skill and suspended-Agent regressions verify recovery. |
| M6: incomplete native prerequisites | README requires Rust as well as the C/OpenSSL toolchain and documents native downloads. The independent public clone built Ortex and Vettore successfully. |

Additional corrections include notification of every verified durable batch even
if subsequent repair fails, monotonic revision coalescing, constant-time decision
identity membership within the history scan, explicit rejection of operational
cursors, and unique UI IDs for records whose references were redacted. An observed
pin mismatch was caused by reading during maintenance; every published manifest
and lockfile is checked for consistency.

The follow-up's small legacy `gam_view` transport suggestion was also applied:
owner timeout is contained by the Runtime, with an additional regression verifying
that a suspended Managed process cannot terminate its caller's Agent.

## Deliberate boundaries

GAM admission, authority, consent and fold laws were not redesigned. Diagnostics
read existing records; they do not own authority or create another ledger.
Checkpoint traces remain partial, and GAM pages still scan retained Scope history.
A checkpoint and a GAM page are separate reads with separate revisions.

The remaining follow-up suggestions are nonblocking responsiveness work: a full
reader pool can postpone a recovery refresh, the UI offers an explicit retry after
a transient read failure, and inspecting a busy Skill can wait up to the bounded
OTP call timeout. Repeated forced process crashes remain subject to the normal
OTP supervisor restart budget; this is not an isolation boundary for hostile BEAM
code. None of these states grants authority, executes an unconfirmed effect or
turns missing diagnostics into a success claim.

See [verification](../VERIFICATION.md) for executed checks and
[the exact source manifest](../../spectre.lock.exs) for the coordinated commits.
