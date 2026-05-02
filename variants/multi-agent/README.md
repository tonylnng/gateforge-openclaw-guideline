# GateForge Multi-Agent Variant

> **Class A — OpenClaw runtime contract** for the five-VM multi-agent topology. The methodology is at [`../../guideline/`](../../guideline/). Read this README before installing.

---

## When to choose this variant

The multi-agent variant is right when:

- You have **multi-team or cross-discipline work** that benefits from concurrent execution.
- You want **explicit role separation** for audit, compliance, or governance reasons.
- The Mac host has the resources for **five VMs** (≥ 24 GB RAM is comfortable).
- You can spend ~60 minutes installing.

If any of those is "no", read [`../single-agent/`](../single-agent/) instead.

---

## Architecture

Five OpenClaw instances run on a Mac host (VMware Fusion) over a Tailscale mesh. The System Architect (VM-1) is the hub. The Designer (VM-2), Developers (VM-3), QC agents (VM-4), and Operator (VM-5) are spokes. A separate **US VM** is the deployment target — it does NOT run OpenClaw.

```
                   ┌──────────────────────┐
                   │  Operator (Telegram) │
                   └──────────┬───────────┘
                              │
    ┌─────────────────────────┴─────────────────────────┐
    │  VM-1 SYSTEM ARCHITECT   (hub + Blueprint owner)  │
    │  Claude Opus 4.6   |   tonic-architect:18789      │
    └─┬───────────┬─────────────┬──────────────┬────────┘
      │ HTTPS     │ HTTPS       │ HTTPS        │ HTTPS
      ▼           ▼             ▼              ▼
   ┌───────┐  ┌──────────┐  ┌───────────┐  ┌──────────┐
   │ VM-2  │  │ VM-3     │  │ VM-4      │  │ VM-5     │
   │Design │  │ Devs 1-N │  │ QC 1-N    │  │ Operator │
   │Sonnet │  │ Sonnet   │  │ MiniMax   │  │ MiniMax  │
   └───────┘  └──────────┘  └───────────┘  └──────────┘
                              │
                              ▼
                   ┌────────────────────┐
                   │  Shared Blueprint  │
                   │  (Git repository)  │
                   │  Read by all VMs   │
                   │  Written by VM-1   │
                   └────────────────────┘
```

| VM | Role | Model | MagicDNS host | Gateway |
|---|---|---|---|---|
| VM-1 | System Architect | `anthropic/claude-opus-4-6` | `tonic-architect.<tailnet>.ts.net` | `:18789` |
| VM-2 | System Designer  | `anthropic/claude-sonnet-4-6` | `tonic-designer.<tailnet>.ts.net` | `:18789` |
| VM-3 | Developers       | `anthropic/claude-sonnet-4-6` | `tonic-developer.<tailnet>.ts.net` | `:18789` |
| VM-4 | QC Agents        | `minimax/minimax-2.7` | `tonic-qc.<tailnet>.ts.net` | `:18789` |
| VM-5 | Operator         | `minimax/minimax-2.7` | `tonic-operator.<tailnet>.ts.net` | `:18789` |
| US VM | Deployment target | (no OpenClaw) | `tonic.<tailnet>.ts.net` | N/A |

---

## Required Reading Order (every agent on every session)

The agent MUST read in this order before doing any work:

1. The VM's **`SOUL.md`** — variant-specific persona and OpenClaw contract.
2. The VM's **`AGENTS.md`** — agent registry, network topology, dispatch rules.
3. The VM's **`USER.md`** — operator context, secrets layout, notification registry.
4. The VM's **`TOOLS.md`** — tool allowlist and sandbox mode.
5. **[`../../guideline/adaptation/MULTI-AGENT-ADAPTATION.md`](../../guideline/adaptation/MULTI-AGENT-ADAPTATION.md)** — variant adapter (translation table, hand-off protocol, peer-review gates).
6. **[`../../guideline/BLUEPRINT-GUIDE.md`](../../guideline/BLUEPRINT-GUIDE.md)** — requirements gathering and Blueprint standards.
7. The active phase's role guide under [`../../guideline/roles/<phase>/`](../../guideline/roles/).
8. The project's `project/state.md` and `project/gateforge_<project_name>.md` (Class C).

The reading order is enforced in each VM's `SOUL.md`. Do not skip a step.

---

## Install

Bring up each VM in order. Detailed steps live in [`docs/INSTALL-GUIDE.md`](docs/INSTALL-GUIDE.md).

```bash
# 1. Clone this repo on every VM
git clone https://github.com/tonylnng/gateforge-openclaw-guideline.git
cd gateforge-openclaw-guideline/variants/multi-agent

# 2. On VM-1
sudo install/setup-vm1-architect.sh

# 3. On VM-2..VM-5 (run the matching script on each VM)
sudo install/setup-vm2-designer.sh    # on VM-2
sudo install/setup-vm3-developers.sh  # on VM-3
sudo install/setup-vm4-qc-agents.sh   # on VM-4
sudo install/setup-vm5-operator.sh    # on VM-5

# 4. Verify connectivity
install/test-connectivity.sh
install/test-communication.sh
```

After every VM is up, the operator pins the project's guideline SHA in the Blueprint:

```yaml
# In <project>-blueprint/project/state.md
guideline_repo: tonylnng/gateforge-openclaw-guideline
guideline_version: 2.0.0
guideline_commit: <40-char SHA from `git rev-parse HEAD`>
```

---

## Layout

```
variants/multi-agent/
├── README.md                          # This file
├── vm-1-architect/                    # System Architect (hub)
│   ├── SOUL.md                        # Class A — runtime contract
│   ├── AGENTS.md
│   ├── USER.md
│   ├── TOOLS.md
│   └── openclaw-config/
│       ├── openclaw.json
│       └── configure-openclaw.sh
├── vm-2-designer/                     # System Designer
│   ├── SOUL.md, AGENTS.md, USER.md, TOOLS.md
│   └── openclaw-config/openclaw.json
├── vm-3-developers/                   # Developer pool
│   ├── SOUL.md, AGENTS.md, USER.md, TOOLS.md
│   ├── dev-01/SOUL.md
│   ├── dev-02/SOUL.md
│   └── openclaw-config/openclaw.json
├── vm-4-qc-agents/                    # QC pool (owns QA + QC phases)
│   ├── SOUL.md, AGENTS.md, USER.md, TOOLS.md
│   ├── qc-01/SOUL.md
│   ├── qc-02/SOUL.md
│   └── openclaw-config/openclaw.json
├── vm-5-operator/                     # Operator
│   ├── SOUL.md, AGENTS.md, USER.md, TOOLS.md
│   └── openclaw-config/openclaw.json
├── install/                           # Install scripts and host-side notifier
│   ├── setup-vm{1..5}-*.sh
│   ├── install-common.sh
│   ├── install-host-notifier.sh
│   ├── test-{communication,connectivity,spoke}.sh
│   ├── host-side/
│   │   ├── gf-notify-architect.{sh,service,path}
│   │   └── gf-replay-deadletter.sh
│   └── openclaw-configs/
│       ├── OPENCLAW-CONFIG-GUIDE.md
│       └── configure-openclaw-spoke.sh
└── docs/
    ├── INSTALL-GUIDE.md
    ├── TEST-COMMUNICATION.md
    ├── _SHARED_FILENAME_COMPLIANCE.md
    ├── _SHARED_NOTIFICATION_PROTOCOL.md
    └── _SHARED_SECRETS_SECTION.md
```

The methodology files (`BLUEPRINT-GUIDE.md`, role guides, adaptation files) are NOT in this directory — they live in [`../../guideline/`](../../guideline/) and are shared with the single-agent variant.

---

## Migration from `gateforge-openclaw-configs` (legacy repo)

The legacy repo `tonylnng/gateforge-openclaw-configs` was archived at v2.0.0. Migration steps:

1. On each VM, replace the legacy clone with this repo:
   ```bash
   cd /opt && sudo rm -rf gateforge-openclaw-configs
   sudo git clone https://github.com/tonylnng/gateforge-openclaw-guideline.git
   cd gateforge-openclaw-guideline/variants/multi-agent
   ```
2. The OpenClaw workspace path may change. Update each VM's `openclaw.json` to point at the new SOUL/AGENTS/USER/TOOLS location:
   ```
   /opt/gateforge-openclaw-guideline/variants/multi-agent/vm-N-<role>/
   ```
3. Restart OpenClaw on each VM. Confirm the boot logs read every Class A file plus the active `guideline/...` files.
4. Update each project's `state.md` to pin the new repo's commit SHA at v2.0.0.
5. Run `install/test-communication.sh` to confirm cross-VM dispatch still works end-to-end.

See also [`docs/INSTALL-GUIDE.md`](docs/INSTALL-GUIDE.md) for fresh-install steps.
