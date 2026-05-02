# Tools Configuration — VM-5 (Operator)

## Allowed Tools

| Tool | Purpose |
|------|---------|
| `exec` | Execute shell commands (sandboxed — `sandbox.mode: "all"`, `scope: "agent"`) — deployment scripts, CI/CD |
| `read` | Read files from workspace, deployment configs, and Blueprint repo |
| `write` | Write deployment runbooks, release notes, CI/CD configs, monitoring configs |
| `edit` | Edit existing files |
| `apply_patch` | Apply patches to configuration files |
| `web_fetch` | Fetch URLs for health checks, API validation, monitoring endpoints |
| `git` | Git operations (clone, pull, commit, push — deployment configs and release notes) |

## Denied Tools

| Tool | Reason |
|------|--------|
| `sessions_send` | No direct agent communication — all routing through Architect |
| `sessions_spawn` | Cannot spawn agent sessions |
| `browser` | No browser automation needed |
| `message` | No direct human communication — Architect handles Telegram |

## Tool Usage Guidelines

### Deployment via Exec

```bash
# Deploy to US VM via Tailscale SSH
exec("ssh user@tonic.sailfish-bass.ts.net 'cd /opt/app && docker compose pull && docker compose up -d'")

# Check deployment health
exec("ssh user@tonic.sailfish-bass.ts.net 'curl -s http://localhost:3000/api/health'")

# Rollback
exec("ssh user@tonic.sailfish-bass.ts.net 'cd /opt/app && docker compose down && docker tag app:previous app:current && docker compose up -d'")
```

### Health Checks via web_fetch

```bash
# Post-deployment smoke tests
web_fetch("http://tonic.sailfish-bass.ts.net:3000/api/health")
web_fetch("http://tonic.sailfish-bass.ts.net:3000/api/v1/status")
```

### CI/CD Pipeline via Exec

```bash
# Trigger CI pipeline
exec("gh workflow run ci.yml --ref develop")

# Check CI status
exec("gh run list --workflow=ci.yml --limit=5")
```

### Git Operations

- Commit deployment configs: `ops: TASK-XXX — update deployment config`
- Commit release notes: `docs: release vX.Y.Z notes`
- Branch naming: `release/vX.Y.Z` or `hotfix/BUG-XXX`

## Sandbox Mode

`sandbox.mode: "all"`, `scope: "agent"` — All exec commands run in a sandboxed environment. SSH commands to US VM are tunneled through Tailscale.

## Environment Variables

Variables are loaded from the files described in **Secrets & Token Locations** below. The table shows which env-var names this VM expects to resolve at runtime and which file owns them.

| Variable | Source File | Scope | Purpose |
|----------|-------------|-------|---------|
| `MINIMAX_API_KEY` | `~/.config/gateforge/minimax.env` | Agent | MiniMax 2.7 API access |
| `TAILSCALE_AUTH_KEY` | `~/.config/gateforge/tailscale.env` | Agent | Tailscale network access for US VM deployment |
| `GITHUB_TOKEN_READONLY` | `~/.config/gateforge/github-tokens.env` | Agent | GitHub Fine-Grained PAT — read-only (Token A) |
| `GITHUB_TOKEN_RW` | `~/.config/gateforge/github-tokens.env` | Agent | GitHub Fine-Grained PAT — read/write to project code repo for CI/CD (Token D) |
| `GATEWAY_AUTH_TOKEN` | `/opt/secrets/gateforge.env` | Gateway | This VM's gateway auth token |
| `AGENT_SECRET` | `/opt/secrets/gateforge.env` | **Host only** | HMAC secret used by the host notifier. Not exposed to the agent. |
| `ARCHITECT_HOOK_TOKEN` | `/opt/secrets/gateforge.env` | **Host only** | Bearer token used by the host notifier |
| `ARCHITECT_NOTIFY_URL` | `/opt/secrets/gateforge.env` | **Host only** | Target URL for the host notifier |

### MiniMax API Configuration

```json
{
  "provider": "minimax/minimax-2.7",
  "baseUrl": "https://api.minimax.chat/v1"
}
```

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
