# Multi-Agent Adaptation

> **Class B — Methodology adapter.** This file describes how the multi-agent variant ([`variants/multi-agent/`](../../variants/multi-agent/)) executes the methodology in [`guideline/`](../). Read this file together with the active role guide whenever the agent's variant is multi-agent.

---

## 1. Topology in one paragraph

The multi-agent variant runs **five OpenClaw instances** on five isolated VMs over a Tailscale mesh. The System Architect (VM-1) is the **hub**; Designer (VM-2), Developers (VM-3), QC (VM-4), and Operator (VM-5) are **spokes**. All cross-VM traffic is HTTPS to the spoke's Tailscale-MagicDNS hostname on port 18789, authenticated with `Authorization: Bearer ${VMn_GATEWAY_TOKEN}`, with results notified back to VM-1 via HMAC-signed callbacks. There is **no direct spoke-to-spoke communication.**

For exact gateway URLs, port assignments, hub/spoke wiring, HMAC secret layout, and install scripts, see [`variants/multi-agent/README.md`](../../variants/multi-agent/README.md).

---

## 2. Role → VM mapping

This is how the role guides in `guideline/roles/` map onto the five VMs in the multi-agent topology.

| Role guide | Owning VM | Owning agent identity | OpenClaw instance |
|---|---|---|---|
| `roles/pm/PM-GUIDE.md` | VM-1 | `architect` (System Architect / PM) | `vm-1-architect` |
| `roles/system-design/SYSTEM-DESIGN-GUIDE.md` | VM-2 | `designer` (System Designer) | `vm-2-designer` |
| `roles/system-design/RESILIENCE-SECURITY-GUIDE.md` | VM-2 | `designer` | `vm-2-designer` |
| `roles/development/DEVELOPMENT-GUIDE.md` | VM-3 | `dev-01..dev-N` (Developer pool) | `vm-3-developers` |
| `roles/qa/QA-FRAMEWORK.md` | VM-4 | `qc-01..qc-N` (QC pool — owns test design AND execution) | `vm-4-qc-agents` |
| `roles/qc/QC-GUIDE.md` | VM-4 | `qc-01..qc-N` | `vm-4-qc-agents` |
| `roles/operations/MONITORING-OPERATIONS-GUIDE.md` | VM-5 | `operator` | `vm-5-operator` |

> **Note on QA + QC.** In the multi-agent variant, **VM-4 owns both QA (test design) and QC (test execution)**. The two role guides are still separate so the agent reads its responsibilities for each phase distinctly, but they are executed by the same agent pool. References in the methodology to "the QC agent" cover both phases.

---

## 3. Reading-order overrides

Where a role guide refers to a sibling role abstractly ("the System Architect", "the Developer", "the QC agent"), the multi-agent agent should resolve those references to the specific VM/agent identity in the table above. Where a guide refers to a specific runtime detail (gateway URL, MagicDNS hostname, port), use the values from `variants/multi-agent/<vm>/AGENTS.md` — those are authoritative for the runtime.

---

## 4. Hand-off protocol

The methodology is written for a sequence of phases (PM → DESIGN → DEV → QA → QC → OPS). In multi-agent, every phase boundary is also a **VM boundary**. Hand-offs therefore use **explicit network calls plus signed notifications**:

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Outbound dispatch (Architect → spoke):                                    │
│                                                                            │
│   POST https://tonic-<spoke>.sailfish-bass.ts.net:18789/hooks/agent        │
│   Authorization: Bearer ${VMn_GATEWAY_TOKEN}                               │
│   Content-Type: application/json                                           │
│   Body: structured JSON (see Appendix A in BLUEPRINT-GUIDE)                │
│                                                                            │
│ Result flow (spoke → Architect):                                           │
│                                                                            │
│   1. Spoke writes its deliverable to the Blueprint repo and                │
│      pushes the commit.                                                    │
│   2. Spoke's host-side `gf-notify-architect.service` watches               │
│      the push, signs the payload with HMAC-SHA256 using its                │
│      VMn_AGENT_SECRET, and POSTs to                                        │
│      https://tonic-architect.sailfish-bass.ts.net:18789/hooks/agent        │
│   3. Architect verifies the signature against the secret in                │
│      USER.md → Agent Notification Registry, then proceeds                  │
│      with quality-gate evaluation.                                         │
└──────────────────────────────────────────────────────────────────────────┘
```

Wherever the methodology says *"the agent transitions to the next phase"*, the multi-agent agent reads it as *"the Architect closes the current task, dispatches the next task to the next VM, and updates `status.md` after the HMAC-verified callback arrives."*

---

## 5. Quality-gate evaluation

The methodology's phase-exit checklists are evaluated by the **System Architect (VM-1)**, not by the producing spoke. The producing spoke writes its self-review checklist into the Blueprint commit; the Architect re-runs it as a **peer-review** before approving the gate.

This is a key strength of the multi-agent variant: **two-pass review** (self + peer) at every gate. Single-agent loses this and compensates by requiring an explicit Telegram-approved boundary on every `Approved` document transition — see [`SINGLE-AGENT-ADAPTATION.md`](SINGLE-AGENT-ADAPTATION.md).

---

## 6. Conflict resolution

Where the methodology says *"if a conflict arises, escalate"*, multi-agent resolves it as follows:

1. The detecting agent posts an `agent-disagreement` payload to the Architect (VM-1).
2. The Architect arbitrates against the Blueprint (the single source of truth) and writes a `decision-log.md` entry.
3. If the Architect cannot resolve, the Architect escalates to the human operator via Telegram with a structured summary.

After **three retries on the same task**, the Architect must escalate to the human regardless. This cap is explicit in `vm-1-architect/USER.md`.

---

## 7. Filename, commit, and audit conventions

These rules are unchanged from the methodology. They apply identically in multi-agent:

- All-lowercase markdown filenames except top-level capitalised guides (`SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`, `*-GUIDE.md`, `*-FRAMEWORK.md`).
- Conventional commits with phase prefix in subject and `GateForge-Phase` / `GateForge-Iteration` / `GateForge-Status` / `GateForge-Summary` trailers.
- Maximum three retries per task before human escalation.

---

## 8. What is multi-agent-only

The following constructs **only** exist in multi-agent. If you see a reference in the methodology that depends on them, you are reading the multi-agent execution path:

- Per-VM `OPENCLAW_TOKEN`, `${VMn_GATEWAY_TOKEN}`, `${VMn_AGENT_SECRET}`.
- `gf-notify-architect.service` host-side notifier (systemd unit, watch + HMAC sign + POST).
- `Authorization: Bearer` headers on cross-VM dispatch.
- `AgentId` field in dispatch payloads (e.g. `dev-01`, `qc-02`).
- Per-VM Tailscale-MagicDNS hostnames (`tonic-<role>.sailfish-bass.ts.net`).
- Cross-VM peer review at quality gates.

If your variant's `AGENTS.md` does not declare remote agents, you are not running multi-agent — read [`SINGLE-AGENT-ADAPTATION.md`](SINGLE-AGENT-ADAPTATION.md) instead.
