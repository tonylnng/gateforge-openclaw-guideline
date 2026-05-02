# Tools Configuration — VM-3 (Developers)

## Allowed Tools

| Tool | Purpose |
|------|---------|
| `exec` | Execute shell commands (sandboxed — `sandbox.mode: "all"`, `scope: "agent"`) |
| `read` | Read files from workspace, project repo, and Blueprint repo |
| `write` | Write code, documentation, and configuration files |
| `edit` | Edit existing files |
| `apply_patch` | Apply code patches |
| `git` | Git operations (clone, pull, commit, push to feature branches) |

## Denied Tools

| Tool | Reason |
|------|--------|
| `sessions_send` | Denied for cross-VM communication — only used intra-VM between dev agents |
| `sessions_spawn` | Cannot spawn agent sessions |
| `browser` | No browser automation — focus on code |
| `message` | No direct human communication |
| `web_search` | No web search — use Blueprint and project docs as reference |

> **Note**: `sessions_send` is available between dev agents on the same VM (dev-01 ↔ dev-02) for integration coordination. It is denied for cross-VM use.

## Tool Usage Guidelines

### Git Workflow

```bash
# Start a new feature
git checkout develop
git pull origin develop
git checkout -b feature/TASK-XXX-description

# Commit work
git add .
git commit -m "feat: TASK-XXX — implement module description"

# Push to remote
git push origin feature/TASK-XXX-description
```

- Branch from: `develop`
- Branch naming: `feature/TASK-XXX-short-description`
- Do NOT merge — Architect or Operator handles merges

### Exec (Sandboxed)

Use `exec` for:
- Running linters and formatters
- Running unit tests locally
- Building/compiling code
- Installing dependencies
- Running database migrations (local dev)

## Sandbox Mode

`sandbox.mode: "all"`, `scope: "agent"` — All exec commands run in a sandboxed environment scoped to each agent's workspace. Agents cannot access each other's filesystems.

## Environment Variables

Variables are loaded from the files described in **Secrets & Token Locations** below. The table shows which env-var names this VM expects to resolve at runtime and which file owns them.

| Variable | Source File | Scope | Purpose |
|----------|-------------|-------|---------|
| `ANTHROPIC_API_KEY` | `~/.config/gateforge/anthropic.env` | Agent | Claude Sonnet 4.6 API access |
| `GITHUB_TOKEN_READONLY` | `~/.config/gateforge/github-tokens.env` | Agent | GitHub Fine-Grained PAT — read-only across all repos (Token A) |
| `GITHUB_TOKEN_RW` | `~/.config/gateforge/github-tokens.env` | Agent | GitHub Fine-Grained PAT — read/write to the project code repo (Token C) |
| `GATEWAY_AUTH_TOKEN` | `/opt/secrets/gateforge.env` | Gateway | This VM's gateway auth token (validates inbound dispatch from Architect) |
| `AGENT_SECRET` | `/opt/secrets/gateforge.env` | **Host only** | HMAC secret used by `gf-notify-architect.sh`. Not exposed to the agent. |
| `ARCHITECT_HOOK_TOKEN` | `/opt/secrets/gateforge.env` | **Host only** | Bearer token used by the host notifier |
| `ARCHITECT_NOTIFY_URL` | `/opt/secrets/gateforge.env` | **Host only** | Target URL for the host notifier |

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
