# GateForge Single-Agent Variant

> **Class A — OpenClaw runtime contract** for the one-VM single-agent topology. The methodology is at [`../../guideline/`](../../guideline/). Read this README before installing.

---

## When to choose this variant

The single-agent variant is right when:

- You're working **solo or in a very small team**.
- The project is a **prototype, internal tool, or maintenance project**.
- You don't need parallel execution across roles.
- You want **~5 minutes of setup**, not 60.

If you outgrow it, migration to multi-agent is straightforward — the Blueprint is identical. See [`../multi-agent/`](../multi-agent/) and [`docs/MIGRATION-FROM-MULTI-AGENT.md`](docs/MIGRATION-FROM-MULTI-AGENT.md).

---

## Architecture

One OpenClaw instance on one VM. The agent role-switches through PM → DESIGN → DEV → QA → QC → OPS by reading the matching guide and updating `project/state.md`.

```
                ┌──────────────────────────┐
                │  Operator (Telegram)     │
                └────────────┬─────────────┘
                             │
              ┌──────────────▼──────────────┐
              │  OpenClaw `gateforge-single`│
              │  Claude Sonnet 4.6          │
              │                             │
              │   Phase machine             │
              │   PM → DESIGN → DEV →       │
              │   QA → QC → OPS             │
              └──────────────┬──────────────┘
                             │
                             ▼
                ┌──────────────────────────┐
                │  Blueprint Git repo      │
                │  + Code Git repo         │
                └──────────────────────────┘
```

| Component | Value |
|---|---|
| VM count | 1 |
| OpenClaw instances | 1 |
| Model | `anthropic/claude-sonnet-4-6` |
| Agent identity | `gateforge-single` |
| Workspace | `~/.openclaw/workspace` |

---

## Required Reading Order (every session)

The agent MUST read in this order before doing any work:

1. **`agent-workspace/SOUL.md`** — variant-specific persona, phase machine, operating rules.
2. **`agent-workspace/AGENTS.md`** — agent registry (one entry: `gateforge-single`).
3. **`agent-workspace/USER.md`** — operator context, secrets layout.
4. **`agent-workspace/TOOLS.md`** — tool allowlist and sandbox mode.
5. **[`../../guideline/adaptation/SINGLE-AGENT-ADAPTATION.md`](../../guideline/adaptation/SINGLE-AGENT-ADAPTATION.md)** — variant adapter (translation table, self-review discipline, Telegram-gated approval rules).
6. **[`../../guideline/BLUEPRINT-GUIDE.md`](../../guideline/BLUEPRINT-GUIDE.md)** — requirements gathering and Blueprint standards.
7. The active phase's role guide under [`../../guideline/roles/<phase>/`](../../guideline/roles/).
8. The project's `project/state.md` and `project/gateforge_<project_name>.md` (Class C).

Steps 5–7 are mandatory on **every phase entry**. Single-agent quality depends on re-reading the role guide rather than working from memory of a previous phase.

---

## Install

This variant is **manual copy-and-go**. No setup scripts.

```bash
# 1. Clone this repo on the VM that runs OpenClaw
git clone https://github.com/tonylnng/gateforge-openclaw-guideline.git
cd gateforge-openclaw-guideline/variants/single-agent

# 2. Copy the agent workspace to OpenClaw's workspace dir
cp -r agent-workspace/. ~/.openclaw/workspace/

# 3. Configure OpenClaw to point at the agent
#    - sandbox.mode = "all" (Docker-backed; needed because the same agent runs code)
#    - hook token, agent ID = "gateforge-single"
#    - models: anthropic/claude-sonnet-4-6
#
#    See agent-workspace/TOOLS.md and USER.md for the full env-var list.

# 4. Place secrets into the standard locations
#    /opt/secrets/gateforge.env                        (root:root, 0600)
#    ~/.config/gateforge/github-tokens.env             (user, 0600)
#    ~/.config/gateforge/{anthropic,telegram,...}.env  (user, 0600)

# 5. Start OpenClaw and verify the agent boots
```

After OpenClaw is up, pin the project's guideline SHA in the Blueprint:

```yaml
# In <project>-blueprint/project/state.md
guideline_repo: tonylnng/gateforge-openclaw-guideline
guideline_version: 2.0.0
guideline_commit: <40-char SHA from `git rev-parse HEAD`>
```

---

## Layout

```
variants/single-agent/
├── README.md                          # This file
├── agent-workspace/                   # ← Copy this whole folder into OpenClaw's workspace
│   ├── SOUL.md                        # Class A — persona + phase machine
│   ├── AGENTS.md                      # Class A — single-agent registry
│   ├── USER.md                        # Class A — operator context, channels, secrets
│   └── TOOLS.md                       # Class A — tool allowlist + env-var table
├── install/                           # (currently empty — manual copy is the install)
└── docs/
    ├── COMPARISON-VS-MULTI-AGENT.md
    └── MIGRATION-FROM-MULTI-AGENT.md
```

The methodology files (`BLUEPRINT-GUIDE.md`, role guides, adaptation files) are NOT in this directory — they live in [`../../guideline/`](../../guideline/) and are shared with the multi-agent variant.

---

## Migration from `gateforge-openclaw-single` (legacy repo)

The legacy repo `tonylnng/gateforge-openclaw-single` was archived at v2.0.0. Migration steps:

1. Clone this repo on the VM:
   ```bash
   cd ~ && rm -rf gateforge-openclaw-single
   git clone https://github.com/tonylnng/gateforge-openclaw-guideline.git
   cd gateforge-openclaw-guideline/variants/single-agent
   ```
2. Re-copy the agent workspace:
   ```bash
   cp -r agent-workspace/. ~/.openclaw/workspace/
   ```
3. Update OpenClaw's workspace path in `openclaw.json` if it pointed at the old layout.
4. Update the project's `state.md` to pin the new repo's commit SHA at v2.0.0.
5. Restart OpenClaw and confirm the agent boots reading the new paths.
6. Run a read-only audit pass before resuming the phase machine — see [`docs/MIGRATION-FROM-MULTI-AGENT.md`](docs/MIGRATION-FROM-MULTI-AGENT.md) for the audit checklist.
