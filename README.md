# GateForge — OpenClaw Agentic SDLC Guideline

> **Single source of truth** for the GateForge Agentic SDLC pipeline — methodology, role guides, and OpenClaw runtime contracts for both the multi-agent and single-agent variants.

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](./VERSION) [![License](https://img.shields.io/badge/license-Proprietary-lightgrey.svg)](./LICENSE) [![Status](https://img.shields.io/badge/status-active-success.svg)](#release-status)

---

## What Is GateForge

GateForge is an **OpenClaw-based agentic Software Development Lifecycle (SDLC) pipeline**. It uses one or more AI agents — each running on its own OpenClaw instance — to walk a project from requirements to production deployment under industry-standard methodology (IEEE 830, ISO 25010, C4, OWASP, IEEE 829, ISTQB, SRE, ITIL, SemVer).

GateForge agents are **not** chatbots producing free-form output. Every phase has a written guideline, a phase-exit checklist, and a quality gate. The methodology is the value; the topology is an implementation choice.

This repository provides **two topologies** that share the same methodology:

| Variant | VMs | OpenClaw instances | Best for |
|---|---|---|---|
| **[Multi-agent](variants/multi-agent/)** | 5 | 5 (Architect, Designer, Devs, QC, Operator) | Multi-team, cross-discipline, parallel work |
| **[Single-agent](variants/single-agent/)** | 1 | 1 (one agent role-switches through every phase) | Solo / small-team projects, prototypes, internal tools |

Both variants read the **same** methodology from [`guideline/`](guideline/). When the methodology is upgraded, both variants benefit immediately — no merge, no fork.

---

## Repository Layout

```
gateforge-openclaw-guideline/
├── README.md                               # This file
├── CONTRIBUTING.md                         # Authoring rules + Class A/B/C file policy
├── CHANGELOG.md                            # SemVer history
├── VERSION                                 # Current SemVer
│
├── guideline/                              # ← Single source of truth (methodology)
│   ├── BLUEPRINT-GUIDE.md
│   ├── roles/
│   │   ├── pm/PM-GUIDE.md
│   │   ├── system-design/
│   │   │   ├── SYSTEM-DESIGN-GUIDE.md
│   │   │   └── RESILIENCE-SECURITY-GUIDE.md
│   │   ├── development/DEVELOPMENT-GUIDE.md
│   │   ├── qa/QA-FRAMEWORK.md
│   │   ├── qc/QC-GUIDE.md
│   │   └── operations/MONITORING-OPERATIONS-GUIDE.md
│   └── adaptation/
│       ├── MULTI-AGENT-ADAPTATION.md       # peer review, HMAC, gateway dispatch
│       └── SINGLE-AGENT-ADAPTATION.md      # role-switch, self-review, no HMAC
│
├── variants/
│   ├── multi-agent/                        # 5-VM OpenClaw runtime contract
│   │   ├── README.md                       # Operator install instructions
│   │   ├── vm-{1..5}-*/                    # Per-VM SOUL/AGENTS/USER/TOOLS + openclaw.json
│   │   ├── install/                        # setup-vm*.sh, install-common.sh, etc.
│   │   └── docs/                           # INSTALL-GUIDE, TEST-COMMUNICATION
│   │
│   └── single-agent/                       # 1-VM OpenClaw runtime contract
│       ├── README.md
│       ├── agent-workspace/                # SOUL/AGENTS/USER/TOOLS
│       ├── install/
│       └── docs/                           # COMPARISON-VS-MULTI-AGENT, MIGRATION
│
├── templates/
│   └── gateforge_PROJECT_TEMPLATE.md       # Class C scaffold (per-project file)
│
└── tools/
    ├── guard-class-ab.sh                   # Pre-commit guard (block edits to Class A/B)
    └── bootstrap-project.sh                # Project bootstrap helper
```

---

## Two-Layer Architecture

GateForge documents are split into two clear layers:

### Layer 1 — Methodology (`guideline/`)

The **how** of building software the GateForge way. Topology-agnostic. Updated centrally; every project and every variant reads from here.

- `BLUEPRINT-GUIDE.md` — requirements gathering, Blueprint document standards, traceability
- `roles/<phase>/*.md` — phase-specific role guides (PM, DESIGN, DEV, QA, QC, OPS)
- `adaptation/*.md` — narrow deltas between multi-agent and single-agent execution

### Layer 2 — Runtime contract (`variants/`)

The **where** and **with what** the agent runs: SOUL, AGENTS, USER, TOOLS, OpenClaw configuration files, and install scripts. Variant-specific because the multi-agent topology requires HMAC notifications, gateway URLs, and per-VM tokens, while the single-agent topology does not.

The runtime contract files reference the methodology by relative path:

```markdown
# In variants/multi-agent/vm-1-architect/SOUL.md
Read in order:
  1. This SOUL.md
  2. ../../../guideline/adaptation/MULTI-AGENT-ADAPTATION.md
  3. ../../../guideline/BLUEPRINT-GUIDE.md
  4. ../../../guideline/roles/<active-phase>/<GUIDE>.md
```

---

## Quick Start

### Pick a variant

- **Solo dev / prototype / internal tool** → [`variants/single-agent/`](variants/single-agent/) — ~5 minutes to install, one Telegram thread.
- **Team / multi-discipline / parallel work** → [`variants/multi-agent/`](variants/multi-agent/) — ~60 minutes to install, five VMs, hub-and-spoke.

Each variant's `README.md` walks through the install and pinning steps.

### Pin a guideline SHA per project

When a project is bootstrapped, the agent records the guideline commit SHA in the project's `state.md`:

```yaml
# In <project>-blueprint/project/state.md
guideline_repo: tonylnng/gateforge-openclaw-guideline
guideline_version: 2.0.0
guideline_commit: <40-char SHA>
```

The agent re-reads from this pinned SHA for the project's life. Upgrades require an explicit Telegram-approved boundary (`Upgrade guideline to v2.1.0 — Approved`). See [CONTRIBUTING.md § Pinning](CONTRIBUTING.md#guideline-pinning-discipline).

---

## Versioning

This repo follows **Semantic Versioning 2.0.0** with GateForge-specific semantics:

| Bump | Trigger |
|---|---|
| **MAJOR** (`X.0.0`) | Methodology change requiring project re-baseline. Existing projects must explicitly migrate. |
| **MINOR** (`x.Y.0`) | Additive checklists, new sections, new role guides, new variant. Backwards-compatible. |
| **PATCH** (`x.y.Z`) | Wording, typo, or clarification. No behaviour change. |

Each release ships a Git tag (`v2.0.0`, `v2.0.1`, …) and a `CHANGELOG.md` entry. Branching is **trunk-based**: every change lands on `main`; releases are tagged from `main`.

See [CONTRIBUTING.md § Versioning](CONTRIBUTING.md#versioning) for full rules.

---

## Release Status

| Version | Date | Status |
|---|---|---|
| 2.0.0 | 2026-05-02 | Active — initial consolidation from `gateforge-openclaw-configs` and `gateforge-openclaw-single` |

The two source repositories (`gateforge-openclaw-configs`, `gateforge-openclaw-single`) are **archived** as of v2.0.0. All future work happens here.

---

## Related Repositories

| Repo | Role |
|---|---|
| [`tonylnng/gateforge-blueprint-template`](https://github.com/tonylnng/gateforge-blueprint-template) | Per-project Blueprint template (cloned at project bootstrap) |
| [`tonylnng/gateforge-openclaw-configs`](https://github.com/tonylnng/gateforge-openclaw-configs) | **Archived** — superseded by `variants/multi-agent/` in this repo |
| [`tonylnng/gateforge-openclaw-single`](https://github.com/tonylnng/gateforge-openclaw-single) | **Archived** — superseded by `variants/single-agent/` in this repo |

---

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR. The most important rules:

1. **Class A/B/C file policy** — don't put project-specific content in this repo. Per-project content lives in each project's Blueprint repo as `project/gateforge_<project_name>.md`.
2. **Trunk-based + tags** — work on short-lived branches, merge to `main`, tag releases.
3. **SemVer with intent** — bump MAJOR only when projects must re-baseline.

---

## License

Proprietary — © Tony NG. See [LICENSE](LICENSE).
