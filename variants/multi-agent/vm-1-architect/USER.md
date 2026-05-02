# User Context — GateForge

## Project Owner

- **Name**: the end-user
- **Role**: CTO / Project Lead
- **Communication**: Telegram (primary channel to System Architect)

## Project: GateForge

GateForge is a multi-agent SDLC pipeline that uses 5 isolated OpenClaw instances on Mac (VMware Fusion) to manage the full software development lifecycle — from requirements to production deployment.

## Architecture Overview

- **5 VMs on Mac** (VMware Fusion, Tailscale VPN network)
  - VM-1: System Architect (Claude Opus 4.6) — you are here
  - VM-2: System Designer (Claude Sonnet 4.6)
  - VM-3: Developers (Claude Sonnet 4.6) — multiple agents
  - VM-4: QC Agents (MiniMax 2.7) — multiple agents
  - VM-5: Operator (MiniMax 2.7)
- **US VM**: Deployment target only (UAT and Production). No OpenClaw. Accessed via Tailscale.
- **Orchestration**: Lobster Pipeline (YAML-defined, deterministic) from day 1
- **Blueprint**: Git-managed document set — single source of truth

## User Preferences

- Structured, practical, quality-gate-driven approach
- All inter-agent communication must use structured JSON
- No free-form prose between agents
- Deterministic pipeline orchestration (Lobster) preferred over LLM-driven sequencing
- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`
- Maximum 3 retries per task before human escalation

## Shared Resources

### GitHub Repositories

| Repository | Purpose | Architect Access |
|-----------|---------|------------------|
| `tonylnng/gateforge-openclaw-configs` | Agent configuration — SOUL.md, TOOLS.md, install scripts | **Read-only** (Token A) |
| `tonylnng/gateforge-blueprint-template` | Standardised Blueprint template — cloned per project, updated with improved standards over time | **Read-only** (Token A) |
| `tonylnng/<project>-blueprint` | Per-project working Blueprint — requirements, architecture, designs, status, backlog, decision log | **Read/write** (Token B) — Architect is the sole writer |
| `tonylnng/<project>-code` | Per-project source code | **Read-only** (Token A) — Developers and Operator write |

### Other Shared Resources

- **Deployment Target**: `user@tonic.sailfish-bass.ts.net` (US VM via Tailscale)

## Agent Notification Registry

This is the source of truth for verifying HMAC signatures on inbound notifications. Each spoke agent has a unique secret used to sign payloads. The secret is **never transmitted** — only an HMAC-SHA256 signature.

> **SECURITY**: This registry is stored locally on VM-1 only. It is NEVER committed to Git or shared with other agents. Each spoke VM holds only its own secret.

| Source VM | Role | HMAC Secret | Tailscale Domain | Status |
|-----------|------|------------|------------------|--------|
| vm-2 | System Designer | `${VM2_AGENT_SECRET}` | `tonic-designer.sailfish-bass.ts.net` | Registered |
| vm-3 | Developers | `${VM3_AGENT_SECRET}` | `tonic-developer.sailfish-bass.ts.net` | Registered |
| vm-4 | QC Agents | `${VM4_AGENT_SECRET}` | `tonic-qc.sailfish-bass.ts.net` | Registered |
| vm-5 | Operator | `${VM5_AGENT_SECRET}` | `tonic-operator.sailfish-bass.ts.net` | Registered |

Generate secrets with:
```bash
openssl rand -hex 32   # 64-character random hex string per VM
```

### Hook Configuration

The Architect's OpenClaw hook endpoint is configured in `openclaw.json`:

```json
{
  "hooks": {
    "enabled": true,
    "token": "${ARCHITECT_HOOK_TOKEN}",
    "path": "/hooks",
    "allowedAgentIds": ["architect"]
  }
}
```

### HMAC Verification Pseudocode

```
ON notification received:
  sourceVm = request.headers["X-Source-VM"]
  signature = request.headers["X-Agent-Signature"]
  body = request.body (raw string)
  
  IF sourceVm NOT IN ["vm-2", "vm-3", "vm-4", "vm-5"]:
    LOG "[SECURITY] Unknown VM: {sourceVm}"
    REJECT
  
  secret = registry[sourceVm].hmacSecret
  expectedSig = HMAC-SHA256(body, secret)
  
  IF signature != expectedSig:
    LOG "[SECURITY] HMAC mismatch for {sourceVm}"
    REJECT
  
  timestamp = JSON.parse(body).metadata.timestamp
  IF abs(NOW - timestamp) > 5 minutes:
    LOG "[SECURITY] Stale notification from {sourceVm} (replay?)"
    REJECT
  
  ACCEPT → process based on priority level
```

### Why HMAC Instead of Secret-in-Body

| Concern | Secret in body | HMAC signature |
|---------|---------------|----------------|
| Secret exposed in transit? | Yes | No — only the signature |
| Replay protection | No | Yes — timestamp + 5-min window |
| Forgery if intercepted | Trivial | Impossible without the secret |

---

## Secrets & Token Locations

GateForge separates secrets by owner and lifetime. You MUST read and write tokens only at the locations listed below. Do not create ad-hoc `.env` files elsewhere, and do not inline secrets in commits, prompts, or logs.

| Secret Class | Location | Permissions | Owner |
|---|---|---|---|
| **GateForge platform tokens** (HMAC, gateway, hook tokens, Architect URL, Tailscale auth) | `/opt/secrets/gateforge.env` | `root:root` · `0600` | Host / systemd only |
| **GitHub tokens** (fine-grained PATs, machine-user tokens) | `~/.config/gateforge/github-tokens.env` | `$USER:$USER` · `0600` | OpenClaw agent user |
| **All other application tokens** (LLM provider keys, MiniMax, Brave Search, Telegram, 3rd-party SaaS) | `~/.config/gateforge/<app>.env` (one file per app, e.g. `anthropic.env`, `minimax.env`, `telegram.env`, `brave.env`) | `$USER:$USER` · `0600` | OpenClaw agent user |

### Loading order

1. The systemd service for the OpenClaw gateway sources `/opt/secrets/gateforge.env` at start.
2. The agent user's shell profile sources every file under `~/.config/gateforge/*.env`.
3. `openclaw.json` references variables by name (e.g. `${ANTHROPIC_API_KEY}`); resolution follows shell environment first, then the gateway's EnvironmentFile.

### Rules for agents

- **Never print a secret.** Treat any value loaded from these paths as opaque. Do not echo, log, or commit it.
- **Never copy secrets into task payloads.** Reference them by env-var name; the host resolves the value.
- **Never write to `/opt/secrets/gateforge.env`.** It is managed exclusively by `install/setup-vmN-*.sh`.
- **When a new third-party token is needed**, request it via an `[INFO]` notification with a proposed filename (`~/.config/gateforge/<app>.env`) and the env-var names required. The Architect and human operator provision it.
- **When in doubt about where a token lives**, check this table. If a path is not listed, the token does not exist yet — request it, do not invent a location.

### Host-side notifier (spokes only: VM-2, VM-3, VM-4, VM-5)

The `gf-notify-architect` systemd service reads `/opt/secrets/gateforge.env` directly. The agent does NOT need `AGENT_SECRET`, `ARCHITECT_HOOK_TOKEN`, or `ARCHITECT_NOTIFY_URL` in its own environment — they are kept off the LLM's context deliberately.
