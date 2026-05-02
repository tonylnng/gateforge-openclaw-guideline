# GateForge Single-Agent Variant

> **One OpenClaw. One agent. The full software development lifecycle.**
>
> Class A — OpenClaw runtime contract for the single-agent topology. The methodology lives at [`../../guideline/`](../../guideline/).

---

## What Is This

The single-agent variant runs **one OpenClaw instance** on one VM. The same agent assumes the **PM, DESIGN, DEV, QA, QC, and OPS** roles in sequence by reading the matching guide on each phase entry. The active phase is recorded in the Blueprint's `project/state.md`; the agent re-reads it at every session start so role-switching is deterministic, not memory-based.

| | **Single-agent (this variant)** | **Multi-agent ([sibling](../multi-agent/))** |
|---|---|---|
| VMs | 1 | 5 |
| OpenClaw instances | 1 | 5 |
| Models | Sonnet 4.6 (default) | Opus 4.6 + Sonnet 4.6 + MiniMax 2.7 |
| Inter-agent comms | None — internal phase transitions | HTTPS Bearer + HMAC notifications |
| Telegram | Single agent | Architect (VM-1) only |
| Quality gates | Self-review + Telegram-approved boundary | Two-pass — self + peer review |
| Setup time | ~5 min (manual copy) | ~60 min |
| Best for | Solo / small-team, prototypes, internal tools | Multi-team, parallel work, audit-heavy |

---

## Architecture

```
                          ┌──────────────────────────┐
                          │   Operator (Telegram)    │
                          └────────────┬─────────────┘
                                       │
                  ┌────────────────────▼────────────────────┐
                  │  Existing OpenClaw                       │
                  │  Agent: gateforge-single                 │
                  │  Model: anthropic/claude-sonnet-4-6      │
                  │                                          │
                  │  Workspace = ~/.openclaw/workspace       │
                  │                                          │
                  │  ┌─────────────────────────────────┐    │
                  │  │  Phase State Machine            │    │
                  │  │                                 │    │
                  │  │   PM → DESIGN → DEV → QA → QC   │    │
                  │  │                          → OPS  │    │
                  │  └─────────────────────────────────┘    │
                  └────────────────┬─────────────────────────┘
                                   │
                ┌──────────────────┼──────────────────┐
                ▼                  ▼                  ▼
        ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
        │  Blueprint  │    │  Project    │    │  Deploy     │
        │  Repo (Git) │    │  Code Repo  │    │  Target     │
        │  Read+Write │    │  Read+Write │    │  (SSH)      │
        └─────────────┘    └─────────────┘    └─────────────┘
```

The agent commits to **Blueprint** and **Code** repos directly. There's no architect-merge gate, no HMAC callbacks, no cross-VM dispatch. Phase transitions are recorded in `project/state.md`; the agent self-enforces phase-exit checklists.

---

## Phase Machine

The Single Agentic SDLC is a state machine. The single OpenClaw agent occupies exactly one state (the **phase**) at a time and role-switches by re-loading the corresponding role guide before continuing.

### States

| Phase   | Role guide (Class B)                                                                      | Primary output                              |
|---------|-------------------------------------------------------------------------------------------|---------------------------------------------|
| `PM`    | `../../guideline/roles/pm/PM-GUIDE.md`                                                    | `project/blueprint/**`                      |
| `DESIGN`| `../../guideline/roles/system-design/SYSTEM-DESIGN-GUIDE.md` + `RESILIENCE-SECURITY-GUIDE.md` | `project/design/**`                       |
| `DEV`   | `../../guideline/roles/development/DEVELOPMENT-GUIDE.md`                                  | source code + `project/dev/**` notes        |
| `QA`    | `../../guideline/roles/qa/QA-FRAMEWORK.md`                                                | `project/qa/test-plan.md`                   |
| `QC`    | `../../guideline/roles/qc/QC-GUIDE.md`                                                    | `project/qc/test-runs/**` + gate verdict    |
| `OPS`   | `../../guideline/roles/operations/MONITORING-OPERATIONS-GUIDE.md`                         | deploy logs + SLO dashboards                |

### Transitions

```mermaid
stateDiagram-v2
    [*] --> PM
    PM --> DESIGN: Approved (Telegram)
    DESIGN --> DEV: Build plan ready
    DEV --> QA: Components compile + unit-pass
    QA --> QC: Test plan ready
    QC --> OPS: Gate Approved
    OPS --> [*]: Live + SLO green

    DESIGN --> PM: Requirement unimplementable
    DEV --> DESIGN: Contract wrong
    DEV --> PM: Scope creep
    QA --> DESIGN: Untestable design
    QC --> DEV: Defect (code)
    QC --> DESIGN: Defect (structural)
    QC --> QA: Test wrong
    QC --> PM: Acceptance criterion wrong
    OPS --> DEV: Hotfix
    OPS --> DESIGN: SLO breach
    OPS --> PM: Missing NFR
```

### Forward-transition guards

| From → To       | Hard gate                                                      | Telegram gate? |
|-----------------|----------------------------------------------------------------|----------------|
| PM → DESIGN     | User replied `Approved` to Blueprint summary                   | **Yes**        |
| DESIGN → DEV    | Build plan self-review checklist all green                     | No             |
| DEV → QA        | All components in build plan compile and pass their unit tests | No             |
| QA → QC         | Test plan self-review checklist all green                      | No             |
| QC → OPS        | Gate verdict `Approved` and Telegram `Approved` (prod only)    | **Yes (prod)** |
| OPS → done      | SLOs green for the agreed soak window                          | No             |

After **three** back-transitions targeting the same phase for the same project, the agent **must escalate** to the operator before the fourth attempt.

---

## Required Reading Order (every session)

```
   1. agent-workspace/SOUL.md                          ┐
   2. agent-workspace/AGENTS.md                        │  this directory
   3. agent-workspace/USER.md                          │
   4. agent-workspace/TOOLS.md                         ┘
                          │
                          ▼
   5. ../../guideline/adaptation/SINGLE-AGENT-ADAPTATION.md   ┐
   6. ../../guideline/BLUEPRINT-GUIDE.md                      │  shared methodology
   7. ../../guideline/roles/<active-phase>/<GUIDE>.md         ┘
                          │
                          ▼
   8. project/state.md                                 ┐
   9. project/gateforge_<project_name>.md (Class C)    ┘  per-project Blueprint repo
```

Steps 5–7 are mandatory **on every phase entry**. Single-agent quality depends on re-reading the role guide rather than working from memory of a previous phase.

---

## Repository Layout

```
variants/single-agent/
│
├── README.md                          # This file
│
├── agent-workspace/                   ← Copy this whole folder into OpenClaw's workspace
│   ├── SOUL.md                        # Class A — persona + phase machine
│   ├── AGENTS.md                      # Class A — single-agent registry
│   ├── USER.md                        # Class A — operator context, channels, secrets
│   └── TOOLS.md                       # Class A — tool allowlist + env-var table
│
├── install/                           # Currently empty — manual copy is the install
│
└── docs/
    ├── COMPARISON-VS-MULTI-AGENT.md
    └── MIGRATION-FROM-MULTI-AGENT.md
```

The methodology files (`BLUEPRINT-GUIDE.md`, role guides, adaptation files) live in [`../../guideline/`](../../guideline/) and are shared with the multi-agent variant.

---

## Installation — Manual Copy

This variant is **manual copy-and-go**. No setup scripts. The full procedure — with copy-and-paste blocks, verification commands, and an FAQ — lives in:

→ **[`install/MANUAL-SETUP.md`](install/MANUAL-SETUP.md)**

### At a glance (7 steps)

1. **Set workspace paths** — export `GF_GUIDELINE_DIR`, `GF_WORKSPACE_DIR`, `GF_PROJECT_ROOT`.
2. **Clone the guideline** on the VM — working copy tracks `main`; the agent's authoritative pin is the SHA in `state.md`.
3. **Copy the agent workspace files** into OpenClaw's workspace path (`SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`) and symlink the methodology so relative paths resolve.
4. **Create the secrets files** — `/opt/secrets/gateforge.env` (root, platform) and `~/.config/gateforge/*.env` (agent user, per-app).
5. **Point OpenClaw at the workspace** — workspace path, agent ID `gateforge-single`, model `anthropic/claude-sonnet-4-6`, sandbox `all`; wire `EnvironmentFile=/opt/secrets/gateforge.env` into the gateway service.
6. **Create the project Blueprint repo** — pin the guideline commit SHA in `project/state.md`, scaffold the Class C file from `templates/gateforge_PROJECT_TEMPLATE.md`, install the Class A/B pre-commit guard.
7. **Restart and verify** the agent's reading order; smoke-test with a low-stakes first task.

For every command, the trade-offs (e.g. tag-pin vs. main-track), and recovery steps, follow [`install/MANUAL-SETUP.md`](install/MANUAL-SETUP.md). Time estimate: ~15 minutes for a clean run.

---

## Quality Gates — Self-Review + Telegram Backstop

```
       Single agent
            │
            │  1. Phase work in role hat
            │
            │  2. Self-review pass
            │     — re-read role guide
            │     — re-enter the role hat
            │     — run phase-exit checklist
            │       as if reviewing a third
            │       party's work
            │
            │  3. Commit + push
            │
            ▼
   ┌─────────────────────┐
   │  Telegram operator  │  ← MANDATORY at PM exit
   │                     │     and prod OPS gate
   │  "Approved" /       │
   │  "Rework: <reason>" │
   └─────────────────────┘
```

Multi-agent gets **peer review** (the Architect re-runs the producing spoke's checklist before approving the gate). Single-agent has only **self-review**, which is structurally weaker. The **Telegram-approved boundary** is the human-in-the-loop that keeps quality honest.

---

## Bootstrapping a New Project

```mermaid
flowchart LR
    A[Operator: 'start project acme_billing'] --> B[Agent validates name<br/>regex: ^[a-z][a-z0-9_]{2,40}$]
    B --> C[Agent runs<br/>tools/bootstrap-project.sh]
    C --> D[Creates project/<br/>gateforge_acme_billing.md<br/>from template]
    D --> E[Agent records pin in<br/>project/state.md:<br/>guideline_repo, version, commit]
    E --> F[Agent enters PM phase,<br/>reads guideline/roles/pm/PM-GUIDE.md]
    F --> G[Discovery Q&A on Telegram]
```

---

## Migration from `gateforge-openclaw-single` (legacy repo)

The legacy repo `tonylnng/gateforge-openclaw-single` was archived at v2.0.0. Migration:

```
   ┌──────────────────────────────────┐
   │  On the VM running OpenClaw:     │
   │                                  │
   │  cd ~                            │
   │  rm -rf gateforge-openclaw-single│
   │  git clone <new-repo>            │
   │  cd <new-repo>/variants/         │
   │      single-agent                │
   │                                  │
   │  cp -r agent-workspace/.         │
   │     ~/.openclaw/workspace/       │
   │                                  │
   │  Restart OpenClaw                │
   └──────────────────────────────────┘
                  │
                  ▼
   ┌──────────────────────────────────┐
   │  In each project's Blueprint:    │
   │                                  │
   │  Update project/state.md:        │
   │    guideline_repo: <new-repo>    │
   │    guideline_version: 2.0.0      │
   │    guideline_commit: <sha>       │
   │                                  │
   │  Commit with [Ops] phase prefix  │
   └──────────────────────────────────┘
                  │
                  ▼
   ┌──────────────────────────────────┐
   │  Run a read-only audit pass      │
   │  before resuming phase work      │
   │  (see docs/MIGRATION-FROM-       │
   │   MULTI-AGENT.md for the         │
   │   audit checklist)               │
   └──────────────────────────────────┘
```
