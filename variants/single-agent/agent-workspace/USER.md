# User Context — GateForge Single Agentic SDLC

## Project Owner

- **Name**: Tony NG (the operator)
- **Role**: CTO / Project Lead
- **Communication**: Telegram (primary channel to the single agent)

## Project: GateForge Single

GateForge Single Agentic SDLC is a single-VM, single-agent variant of the GateForge multi-agent SDLC pipeline. It collapses the five-role pipeline (Architect, Designer, Developer, QC, Operator) into one OpenClaw agent that walks through every SDLC phase itself.

## Architecture Overview

- **1 VM** (Ubuntu, OpenClaw, optional Tailscale)
- **1 OpenClaw instance** running the `gateforge-single` agent
- **Model**: `anthropic/claude-sonnet-4-6`
- **Blueprint**: per-project Git repository, cloned from `tonylnng/gateforge-blueprint-template`
- **Code**: per-project Git repository
- **Deployment target**: any reachable host (e.g., the same US VM used by the multi-agent variant via Tailscale SSH)

## User Preferences

- Structured, practical, quality-gate-driven approach
- All phase transitions logged in Blueprint
- Conventional commits with phase prefix: `[PM]`, `[Design]`, `[Dev]`, `[QA]`, `[QC]`, `[Ops]`
- Maximum 3 back-transitions before human escalation
- IEEE 830, ISO 25010, C4, OWASP, IEEE 829, ISTQB, SRE, ITIL, SemVer

## Shared Resources

### GitHub Repositories

| Repository | Purpose | Single Agent Access |
|---|---|---|
| `tonylnng/gateforge-openclaw-single` | This repo — agent config, role guides, install scripts | **Read-only** (Token A) |
| `tonylnng/gateforge-blueprint-template` | Standardised Blueprint template — cloned per project | **Read-only** (Token A) |
| `tonylnng/<project>-blueprint` | Per-project working Blueprint | **Read/write** (Token B) |
| `tonylnng/<project>-code` | Per-project source code | **Read/write** (Token C) |

### Other Shared Resources

- **Deployment Target**: `user@<deploy-host>` accessed via SSH (Tailscale or direct)

## Notification Protocol — None

Unlike the multi-agent variant, there is **no HMAC notification protocol**. There are no spokes to notify the hub. Commits are not signed for callback verification. The single agent reads its own state from the Blueprint repo on every session entry.

If you have set up the multi-agent variant before and remember the `gf-notify-architect.service` systemd unit — it does not exist here, and `setup-single.sh` does not create it.

## Hook Configuration

The OpenClaw hook endpoint is still configured because the Telegram channel and any future webhooks (e.g., GitHub push events) need a target:

```json5
{
  hooks: {
    enabled: true,
    token: "${HOOK_TOKEN}",
    path: "/hooks",
    allowedAgentIds: ["gateforge-single"]
  }
}
```

But there is no spoke-to-hub HMAC verification step. You can use the hook for direct GitHub webhooks, cron callbacks, or external system integrations as the project requires.

---

## Secrets & Token Locations

GateForge separates secrets by owner and lifetime. You MUST read and write tokens only at the locations listed below. Do not create ad-hoc `.env` files elsewhere, and do not inline secrets in commits, prompts, or logs.

| Secret Class | Location | Permissions | Owner |
|---|---|---|---|
| **Platform tokens** (gateway, hook, Tailscale auth) | `/opt/secrets/gateforge.env` | `root:root` · `0600` | Host / systemd only |
| **GitHub tokens** (fine-grained PATs, machine-user tokens) | `~/.config/gateforge/github-tokens.env` | `$USER:$USER` · `0600` | OpenClaw agent user |
| **All other application tokens** (Anthropic, Telegram, Brave Search, 3rd-party SaaS) | `~/.config/gateforge/<app>.env` (one file per app, e.g. `anthropic.env`, `telegram.env`, `brave.env`) | `$USER:$USER` · `0600` | OpenClaw agent user |

### Loading order

1. The systemd service for the OpenClaw gateway sources `/opt/secrets/gateforge.env` at start.
2. The agent user's shell profile sources every file under `~/.config/gateforge/*.env`.
3. `openclaw.json` references variables by name (e.g. `${ANTHROPIC_API_KEY}`); resolution follows shell environment first, then the gateway's EnvironmentFile.

### Rules

- **Never print a secret.** Treat any value loaded from these paths as opaque. Do not echo, log, or commit it.
- **Never copy secrets into commits, task notes, or chat messages.** Reference them by env-var name; the host resolves the value.
- **Never write to `/opt/secrets/gateforge.env`.** It is managed exclusively by `install/setup-single.sh`.
- **When a new third-party token is needed**, request it from the human via Telegram with the proposed filename (`~/.config/gateforge/<app>.env`) and env-var names. Do not invent a location.

## What's Different from the Multi-Agent Variant

| Aspect | Multi-Agent | Single Agent |
|---|---|---|
| Per-VM `AGENT_SECRET` | Required (HMAC) | **Not used** |
| `ARCHITECT_HOOK_TOKEN` | Separate from gateway token | Same as `HOOK_TOKEN` (single-purpose) |
| `DESIGNER_TOKEN`, `DEV_TOKEN`, `QC_TOKEN`, `OPERATOR_TOKEN` | Required for cross-VM dispatch | **Not used** |
| `gf-notify-architect.service` | Required on each spoke | **Not installed** |
| `VM{2,3,4,5}_AGENT_SECRET` | Architect verifies inbound HMAC | **Not used** |

Token surface is intentionally smaller. Fewer moving parts, fewer rotation steps.
