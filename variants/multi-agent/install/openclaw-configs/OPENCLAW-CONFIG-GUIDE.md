# GateForge — OpenClaw Hub-and-Spoke Configuration Guide

> Step-by-step guide to configure OpenClaw on all 5 GateForge VMs.
> These scripts **patch** your existing config — they do NOT overwrite it.

---

## Overview

Each VM runs its own OpenClaw Gateway with its own `~/.openclaw/openclaw.json`. The GateForge configuration scripts use `openclaw config set` and `config.patch` to add hub-and-spoke settings **on top of** whatever is already configured (models, auth profiles, channels, API keys, etc.).

| VM | Role | Script | What It Configures |
|----|------|--------|-------------------|
| VM-1 | System Architect (Hub) | `vm-1-architect/configure-openclaw.sh` | Gateway auth, hooks for spoke notifications, Architect agent, cron |
| VM-2 | System Designer (Spoke) | `configure-openclaw-spoke.sh` | Gateway auth, hooks for task dispatch, Designer agent |
| VM-3 | Developers (Spoke) | `configure-openclaw-spoke.sh` | Gateway auth, hooks, multi-agent (dev-01..N), Docker sandbox |
| VM-4 | QC Agents (Spoke) | `configure-openclaw-spoke.sh` | Gateway auth, hooks, multi-agent (qc-01..N), Docker sandbox |
| VM-5 | Operator (Spoke) | `configure-openclaw-spoke.sh` | Gateway auth, hooks, Operator agent, cron, extra tools |

The spoke script auto-detects the VM role from `GATEFORGE_ROLE` in `/opt/secrets/gateforge.env`.

---

## How It Works — CLI Instead of File Copy

Instead of overwriting `openclaw.json`, the scripts use two methods:

### Method 1: `openclaw config set` (simple key-value)

For flat settings like gateway bind, model, logging:

```bash
openclaw config set gateway.bind tailnet
openclaw config set agents.defaults.model.primary "anthropic/claude-opus-4-6"
openclaw config set cron.enabled true
```

This is the safest approach — OpenClaw validates the key path and value type against its schema before writing.

### Method 2: `config.patch` (complex nested objects)

For structured settings like hooks and agent lists, the script uses the Gateway's `config.patch` RPC, which performs a **JSON merge patch** (RFC 7386):

- Objects merge recursively (existing keys preserved, new keys added)
- `null` deletes a key
- Arrays are replaced (not appended)

```bash
openclaw gateway call config.patch --params '{
  "raw": "{ hooks: { enabled: true, token: \"...\", path: \"/hooks\" } }",
  "baseHash": "<current-hash>",
  "note": "GateForge hub config"
}'
```

If the Gateway is not running, the script falls back to a safe file-based JSON merge using Python.

### What gets preserved

| Preserved (not touched) | Configured (added/updated) |
|-------------------------|---------------------------|
| Existing channels (Telegram, Discord, etc.) | `gateway.bind`, `gateway.auth` |
| Auth profiles and API keys | `hooks.*` (webhook endpoints) |
| Model provider configuration | `agents.defaults.model` (primary + fallbacks) |
| Existing tools and skills | `agents.list` (role-specific agents) |
| Sandbox settings (unless code-exec VM) | `session.*`, `cron.*`, `logging.*` |
| Any manual customisations | `sandbox.*` (VM-3/VM-4 only) |

---

## Prerequisites

Before running the config scripts:

1. **OpenClaw is installed and working** — the setup wizard (`openclaw onboard`) should have been completed
2. **GateForge setup scripts have been run** — these generate tokens in `/opt/secrets/gateforge.env`
3. **API keys configured** — model provider keys should already be set up via `openclaw auth add` or the wizard

---

## Step-by-Step Setup

### Step 1 — Run GateForge Setup Scripts (if not done already)

The setup scripts generate the inter-VM communication tokens:

```bash
# On VM-1 (generates tokens for ALL VMs)
sudo bash install/setup-vm1-architect.sh

# On each spoke VM (paste tokens from VM-1 output)
sudo bash install/setup-vm2-designer.sh     # VM-2
sudo bash install/setup-vm3-developers.sh   # VM-3
sudo bash install/setup-vm4-qc-agents.sh    # VM-4
sudo bash install/setup-vm5-operator.sh     # VM-5
```

### Step 2 — Configure OpenClaw on VM-1 (Hub)

```bash
cd ~/gateforge-openclaw-configs/openclaw-configs

# Preview what will change (recommended first)
sudo bash vm-1-architect/configure-openclaw.sh --dry-run

# Apply the configuration
sudo bash vm-1-architect/configure-openclaw.sh

# Restart Gateway (required for gateway.* changes)
openclaw gateway restart
```

### Step 3 — Configure OpenClaw on Each Spoke VM

The same script works on all spoke VMs — it reads `GATEFORGE_ROLE` from `/opt/secrets/gateforge.env` to determine what to configure.

```bash
cd ~/gateforge-openclaw-configs/openclaw-configs

# Preview what will change
sudo bash configure-openclaw-spoke.sh --dry-run

# Apply the configuration
sudo bash configure-openclaw-spoke.sh

# Restart Gateway
openclaw gateway restart
```

### Step 4 — Verify

```bash
# Check the config was applied
openclaw config get gateway.bind           # Should show: tailnet
openclaw config get hooks.enabled          # Should show: true
openclaw config get agents.defaults.model  # Should show the expected model

# Run connectivity tests
sudo bash install/test-connectivity.sh     # From VM-1
sudo bash install/test-spoke.sh            # From any spoke
```

---

## VM-3 and VM-4: Adjusting Agent Count

The spoke script defaults to 3 agents. To change:

### Option A: Set in gateforge.env before running the config script

```bash
# Add to /opt/secrets/gateforge.env
echo "GATEFORGE_AGENT_COUNT=5" | sudo tee -a /opt/secrets/gateforge.env

# Then run the config script
sudo bash configure-openclaw-spoke.sh
```

### Option B: Add agents via CLI after initial config

```bash
# Add dev-04 and dev-05 manually
openclaw agents add --id "dev-04" --workspace ~/.openclaw/workspace-dev-04 --non-interactive
openclaw agents add --id "dev-05" --workspace ~/.openclaw/workspace-dev-05 --non-interactive

openclaw gateway restart
```

### Option C: Remove agents

```bash
openclaw agents delete --id dev-03
openclaw gateway restart
```

---

## What Each Section Does

### Gateway

```bash
openclaw config set gateway.bind tailnet            # Listen on Tailscale IP only
openclaw config set gateway.auth.mode token          # Require Bearer token
openclaw config set gateway.auth.token "$TOKEN"      # Per-VM unique token
openclaw config set gateway.auth.allowTailscale false # No free pass for Tailscale peers
```

All VMs get the same gateway structure. The token is unique per VM — generated by the VM-1 setup script.

### Hooks

The hooks section enables the `/hooks/agent` endpoint on every VM:

- **VM-1 (Hub)**: Receives status notifications from spokes. Uses a **dedicated hook token** (separate from the gateway token).
- **VM-2–5 (Spokes)**: Receive task dispatches from the Architect. Use their **gateway token** for hook auth.

The `mappings` array routes inbound `POST /hooks/agent` requests to the correct agent on that VM.

### Agents

| VM | Pattern | Agent IDs |
|----|---------|-----------|
| VM-1 | Single agent | `architect` |
| VM-2 | Single agent | `designer` |
| VM-3 | Multi-agent | `dev-01`, `dev-02`, `dev-03`, ... |
| VM-4 | Multi-agent | `qc-01`, `qc-02`, `qc-03`, ... |
| VM-5 | Single agent | `operator` |

Multi-agent VMs (VM-3, VM-4) get per-agent workspaces and `agentDir` directories so each agent has isolated files, memory, and sessions.

### Sandbox

| VM | `sandbox.mode` | Why |
|----|---------------|-----|
| VM-1 Architect | `non-main` | No code execution needed |
| VM-2 Designer | `non-main` | No code execution needed |
| VM-3 Developers | `all` (Docker) | Code execution in isolated containers |
| VM-4 QC Agents | `all` (Docker) | Test execution in isolated containers |
| VM-5 Operator | `non-main` | Deployment commands run on host |

### Models

| VM | Primary Model | Fallback |
|----|--------------|----------|
| VM-1 | `anthropic/claude-opus-4-6` | `claude-sonnet-4-6` |
| VM-2 | `anthropic/claude-sonnet-4-6` | `claude-sonnet-4-6` |
| VM-3 | `anthropic/claude-sonnet-4-6` | `claude-sonnet-4-6` |
| VM-4 | `minimax/MiniMax-M2.7` | `claude-sonnet-4-6` |
| VM-5 | `minimax/MiniMax-M2.7` | `claude-sonnet-4-6` |

The scripts only set `agents.defaults.model`. If you have already configured models via `openclaw models set` or the wizard, those per-agent overrides are preserved.

---

## Security Notes

| Concern | How the scripts handle it |
|---------|--------------------------|
| Token uniqueness | Each VM has its own `GATEWAY_AUTH_TOKEN`; VM-1 has a separate `ARCHITECT_HOOK_TOKEN` |
| No Tailscale bypass | `gateway.auth.allowTailscale` is set to `false` — token required even from Tailscale |
| Secret storage | Tokens stay in `/opt/secrets/gateforge.env` (root:root 600) — the JSON file uses `${VAR}` references |
| Sandbox isolation | Code-executing VMs (VM-3, VM-4) use Docker with `network: "none"` |
| Hook token separation | VM-1's hook token is separate from its gateway token — leaked hook token can't control the gateway |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Script says "GATEFORGE_ROLE not set" | Run the VM setup script first (`setup-vmN-*.sh`) |
| `openclaw config set` fails with schema error | Run `openclaw doctor --fix` then retry |
| Config change has no effect | Run `openclaw gateway restart` (gateway.* fields require restart) |
| `config.patch` fails | Gateway may not be running — script falls back to file edit automatically |
| Hook returns 404 | Check `openclaw config get hooks.enabled` — should be `true` |
| Agent not found | Run `openclaw agents list` to verify agent IDs |
| Model not available | Run `openclaw models status --probe` to test provider connectivity |
| Want to undo changes | Restore backup: `cp ~/.openclaw/openclaw.json.bak ~/.openclaw/openclaw.json` |

### Manual Verification Commands

```bash
# View all GateForge-related settings
openclaw config get gateway
openclaw config get hooks
openclaw config get agents
openclaw config get cron

# Check which agents are configured
openclaw agents list
openclaw agents list --bindings

# Test hook endpoint locally
curl -s -X POST http://localhost:18789/hooks/agent \
  -H "Authorization: Bearer $(openclaw config get hooks.token)" \
  -H "Content-Type: application/json" \
  -d '{"message": "test"}'
```

---

## File Reference

```
openclaw-configs/
├── OPENCLAW-CONFIG-GUIDE.md                ← This guide
├── vm-1-architect/
│   ├── configure-openclaw.sh               ← Hub config script
│   └── openclaw.json                       ← Reference template (do NOT copy directly)
├── vm-2-designer/
│   └── openclaw.json                       ← Reference template
├── vm-3-developers/
│   └── openclaw.json                       ← Reference template
├── vm-4-qc-agents/
│   └── openclaw.json                       ← Reference template
├── vm-5-operator/
│   └── openclaw.json                       ← Reference template
└── configure-openclaw-spoke.sh             ← Shared spoke config script (VM-2 through VM-5)
```

The `openclaw.json` files are kept as **reference templates** showing the target state. The actual configuration is done by the shell scripts using CLI commands.

---

*GateForge — Multi-Agent SDLC Pipeline | Designed by Tony NG | April 2026*
