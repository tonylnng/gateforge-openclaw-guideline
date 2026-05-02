# Tools Configuration — VM-4 (QC Agents)

## Allowed Tools

| Tool | Purpose |
|------|---------|
| `exec` | Execute shell commands (sandboxed — `sandbox.mode: "all"`, `scope: "agent"`) — run tests, linters, scanners |
| `read` | Read files from workspace, project code, and Blueprint repo |
| `write` | Write test cases, test reports, and QA documentation |
| `edit` | Edit existing test files |
| `web_fetch` | Fetch URLs for API testing (contract validation, endpoint testing) |
| `git` | Git operations (pull code for inspection — read-only; push test artifacts to feature branches) |

## Denied Tools

| Tool | Reason |
|------|--------|
| `sessions_send` | Denied for cross-VM communication — only used intra-VM between QC agents |
| `sessions_spawn` | Cannot spawn agent sessions |
| `browser` | No browser automation (use Playwright/Cypress via `exec` for E2E tests) |
| `message` | No direct human communication |
| `git (push to code branches)` | QC agents do NOT push code fixes — only test artifacts |

> **Note**: `sessions_send` is available between QC agents on the same VM (qc-01 ↔ qc-02) for test coordination. It is denied for cross-VM use.

## Tool Usage Guidelines

### Test Execution via Exec

```bash
# Unit tests
exec("cd ~/workspace-qc-01/project-repo && npm test")

# API contract testing
exec("cd ~/workspace-qc-01 && npx openapi-validator specs/service-a.openapi.yaml")

# E2E tests
exec("cd ~/workspace-qc-01 && npx playwright test")

# Performance tests
exec("cd ~/workspace-qc-01 && k6 run load-test.js")

# Security scanning
exec("cd ~/workspace-qc-01 && trivy fs --severity HIGH,CRITICAL .")
```

### API Testing via web_fetch

```bash
# Test API endpoints directly
web_fetch("http://dev-environment:3000/api/health")
web_fetch("http://dev-environment:3000/api/v1/users", method="POST", body="{...}")
```

### Git (Read-Only Code Access)

```bash
# Pull latest code for inspection
exec("cd ~/workspace-qc-01/project-repo && git pull origin develop")

# Push test artifacts only
git commit -m "test: TASK-XXX — add test cases for module Y"
git push origin test/TASK-XXX-description
```

## Sandbox Mode

`sandbox.mode: "all"`, `scope: "agent"` — All exec commands run in a sandboxed environment scoped to each agent's workspace.

## Environment Variables

Variables are loaded from the files described in **Secrets & Token Locations** below. The table shows which env-var names this VM expects to resolve at runtime and which file owns them.

| Variable | Source File | Scope | Purpose |
|----------|-------------|-------|---------|
| `MINIMAX_API_KEY` | `~/.config/gateforge/minimax.env` | Agent | MiniMax 2.7 API access |
| `GITHUB_TOKEN_READONLY` | `~/.config/gateforge/github-tokens.env` | Agent | GitHub Fine-Grained PAT — read-only (Token A) |
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
