# Single-Agent Adaptation

> **Class B — Methodology adapter.** This file describes how the single-agent variant ([`variants/single-agent/`](../../variants/single-agent/)) executes the methodology in [`guideline/`](../). Read this file together with the active role guide whenever the agent's variant is single-agent.

---

## 1. Topology in one paragraph

The single-agent variant runs **one OpenClaw instance** on one VM. The same agent assumes the **PM, DESIGN, DEV, QA, QC, and OPS** roles in sequence by reading the matching guide on each phase entry. The active phase is recorded in the Blueprint's `project/state.md`; the agent re-reads it at every session start so role-switching is deterministic, not memory-based.

For exact host requirements, install steps, and the (optional) Tailscale-Serve setup for remote control, see [`variants/single-agent/README.md`](../../variants/single-agent/README.md).

---

## 2. Role → identity mapping

In single-agent, **every role guide in `guideline/roles/`** is executed by the same OpenClaw agent (`gateforge-single`). The agent role-switches by re-reading the guide and updating `project/state.md`.

| Role guide | Phase | Owning agent identity | When to read |
|---|---|---|---|
| `roles/pm/PM-GUIDE.md` | `PM` | `gateforge-single` | First phase; entered on every back-transition |
| `roles/system-design/SYSTEM-DESIGN-GUIDE.md` | `DESIGN` | `gateforge-single` | After PM `Approved` |
| `roles/system-design/RESILIENCE-SECURITY-GUIDE.md` | `DESIGN` | `gateforge-single` | Together with SYSTEM-DESIGN-GUIDE on every DESIGN entry |
| `roles/development/DEVELOPMENT-GUIDE.md` | `DEV` | `gateforge-single` | After DESIGN handoff |
| `roles/qa/QA-FRAMEWORK.md` | `QA` | `gateforge-single` | After DEV phase exit |
| `roles/qc/QC-GUIDE.md` | `QC` | `gateforge-single` | After QA phase exit; **always re-read QA-FRAMEWORK first** |
| `roles/operations/MONITORING-OPERATIONS-GUIDE.md` | `OPS` | `gateforge-single` | After QC `Approved` |

> **Reading the right guide first is mandatory.** The single agent must NEVER start phase work from memory of a previous phase. Re-read the guide on every phase entry, even within the same iteration.

---

## 3. Translation table — multi-agent terms in the methodology

The methodology files were written with the multi-agent topology in mind. When you encounter the following terms, translate them as described:

| Methodology says… | Single-agent reads it as… |
|---|---|
| "the System Architect (VM-1)" | "the agent itself, currently in `PM` phase" |
| "the System Designer (VM-2)" | "the agent itself, currently in `DESIGN` phase" |
| "the Developer (VM-3, dev-01..N)" | "the agent itself, currently in `DEV` phase" |
| "the QC agent (VM-4, qc-01..N)" | "the agent itself, currently in `QA` or `QC` phase" |
| "the Operator (VM-5)" | "the agent itself, currently in `OPS` phase" |
| "dispatch to spoke" / "POST to /hooks/agent" | "transition `phase` in `project/state.md` and re-read the next guide" |
| "HMAC-signed callback" | "`git push` of the phase deliverable; commit trailers carry the audit info" |
| "peer review by the Architect" | "self-review pass: re-enter the role hat and run the phase-exit checklist as if reviewing a third party's work" |
| "submission to VM-1" | "commit and push to the Blueprint repo with the phase prefix in the subject" |
| "Architect arbitrates the conflict" | "the agent escalates on Telegram and waits for the operator's reply" |

---

## 4. Hand-off protocol

In multi-agent, hand-offs are **network calls + HMAC notifications**. In single-agent, hand-offs are **state-machine transitions**:

```
1. Update project/state.md:
     phase: <next>
     iteration: <i>
     last_<prev>_commit: <sha>
2. Commit:
     [<NextPhase>] Begin <next> phase — <iter>
     GateForge-Phase: <NextPhase>
     GateForge-Iteration: <i>
     GateForge-Status: In-Progress
     GateForge-Summary: <one-line>
3. git push
4. Re-read SOUL.md, then guideline/adaptation/SINGLE-AGENT-ADAPTATION.md (this file),
   then guideline/roles/<next-phase>/<GUIDE>.md before continuing.
```

There is no `Authorization: Bearer` header, no HMAC secret, no `gf-notify-architect.service`. Commits are not signed for callback verification because there is no spoke to notify.

---

## 5. Quality-gate evaluation — self-review with Telegram backstop

Multi-agent gets **peer review** (the Architect re-runs the producing spoke's checklist before approving the gate). Single-agent has only **self-review**, which is structurally weaker. To compensate:

- The agent must perform self-review as a **separate sub-task with the role hat re-entered** — not in the same flow that produced the deliverable. Re-read the guide before reviewing.
- **Document approval requires an explicit Telegram `Approved` from the operator** before any document transitions from `In-Review` to `Approved`. This is the **single most important governance hook** in single-agent mode.
- The Telegram-approved boundary is mandatory before:
  - PM → DESIGN
  - QC → OPS (for production deploys)
  - Any guideline-pin upgrade (`Upgrade guideline to vX.Y.Z — Approved`)

Without the human-in-the-loop on document approval, single-agent quality drifts toward vibe-coding. The check is what keeps it honest.

---

## 6. Conflict resolution

Multi-agent resolves conflicts by Architect arbitration. Single-agent has no peer to arbitrate, so:

1. The agent posts a structured `agent-disagreement` summary to Telegram.
2. The agent does NOT proceed until the operator replies with a directive.
3. If the operator's directive contradicts the active role's checklist, the agent must back-transition to PM and revise the Blueprint before continuing.
4. After **three back-transitions on the same task**, the agent escalates to the operator with a Telegram summary and waits.

---

## 7. What is single-agent-only

The following constructs **only** exist in single-agent:

- Phase identities held by a single OpenClaw agent (`gateforge-single`).
- Role-switching via state-machine transitions in `project/state.md`.
- Self-review (no peer review).
- Telegram-gated document approval as the primary quality backstop.
- Mandatory re-reading of the role guide on every phase entry.

The following constructs **do not** exist in single-agent (do not look for them):

- Per-VM `OPENCLAW_TOKEN`, `${VMn_GATEWAY_TOKEN}`, `${VMn_AGENT_SECRET}`.
- `gf-notify-architect.service` (it does not exist; `setup-single.sh` does not create it).
- Cross-VM `agentId` field in any payload — every dispatch is `gateforge-single`.
- HMAC verification on commits.

---

## 8. When to migrate to multi-agent

Signals that you've outgrown single-agent:

- More than ~3 iterations of parallel module development needed at once.
- More than ~50 test cases per iteration (single-agent QC starts queueing real-world work).
- A regulatory audit requires explicit role separation (multi-agent provides this by VM boundary).
- Real human team members join who want their own workspaces.

Migration is straightforward because the Blueprint is unchanged. See [`variants/multi-agent/docs/MIGRATION-FROM-SINGLE.md`](../../variants/multi-agent/docs/MIGRATION-FROM-SINGLE.md) (added in v2.0.0).
