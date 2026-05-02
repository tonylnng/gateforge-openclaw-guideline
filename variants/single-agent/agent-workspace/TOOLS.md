# Tools Configuration — Single Agent

## Allowed Tools

The single agent needs the union of tools previously split across five roles. This is broader than any individual multi-agent role's allowlist.

| Tool | Purpose | Used in Phase(s) |
|---|---|---|
| `read` | Read files from workspace and Blueprint | All |
| `write` | Write files to workspace and Blueprint | All |
| `edit` | Edit existing files | All |
| `apply_patch` | Apply structured patches | DEV, OPS |
| `exec` | Execute shell commands (sandboxed) | DEV, QC, OPS |
| `process` | Launch and manage long-running processes | DEV, QC, OPS |
| `git` | Clone, pull, push, branch, merge | All |
| `web_search` | Web research (Brave) | PM, DESIGN |
| `web_fetch` | Fetch URLs | PM, DESIGN, OPS |
| `browser` | Headless browser for UI tests | QC |
| `cron` | Schedule recurring tasks (monitoring) | OPS |
| `message` | Telegram messages to the operator | All |
| `memory_search` | Search persistent memory store | All |
| `memory_get` | Retrieve memory entries | All |
| `llm-task` | Structured LLM calls with JSON schema | All (advanced) |
| `lobster` | Optional Lobster pipeline runner | All (optional) |

## Denied Tools

None at the OpenClaw level. Discipline is enforced by phase guides and SOUL.md, not tool ACLs.

## Tool Usage Guidelines

### Sandbox Mode

`sandbox.mode: "all"` (Docker-backed). Because the same agent must run code (DEV) and execute tests (QC), the sandbox must support code execution. The Docker sandbox provides:

- Isolated container per session
- No outbound network by default (`network: "none"`)
- 1 vCPU / 1024 MB by default — adjust per project
- Read-only root only when phase = OPS or PM

Override per task by passing sandbox options in the task plan when needed.

### Git Operations

- Branch from `develop` (or `main` if no `develop` exists)
- Branch naming: `iter/<NNN>` for iteration branches; `phase/<phase>-<task-id>` for phase-scoped branches
- Conventional commits with phase prefix (see SOUL.md § Commit Protocol)
- The single agent merges its own iteration branches at iteration close, with the Telegram-gated Go from the operator

### Telegram (Human Interface)

The operator interacts with the agent via Telegram. The agent should:

- Confirm phase entries succinctly
- Report blockers with structured context (phase, current task, missing input)
- Request explicit Go/No-Go for production deployments
- Summarise iteration close with a link to the status report
- Never paste raw stack traces, full logs, or secrets

### Lobster (Optional)

Lobster pipelines can orchestrate phase transitions when you want deterministic flow:

```bash
lobster run workflows/single-sdlc.lobster \
  --arg project=<project-name> \
  --arg requirements="<text>"
```

The provided `workflows/single-sdlc.lobster` walks PM → DESIGN → DEV → QA → QC → OPS with phase exit checklists at each boundary. Without Lobster, the agent runs the same flow LLM-driven from `SOUL.md`.

## Environment Variables

Variables are loaded from the files described in **Secrets & Token Locations** below. The table shows which env-var names this VM expects to resolve at runtime and which file owns them.

| Variable | Source File | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | `~/.config/gateforge/anthropic.env` | Claude Sonnet 4.6 API access |
| `TELEGRAM_BOT_TOKEN` | `~/.config/gateforge/telegram.env` | Telegram channel communication |
| `TELEGRAM_ALLOWED_USER_ID` | `~/.config/gateforge/telegram.env` | Allowlisted Telegram user |
| `BRAVE_SEARCH_API_KEY` | `~/.config/gateforge/brave.env` | Web search tool provider |
| `GITHUB_TOKEN_READONLY` | `~/.config/gateforge/github-tokens.env` | GitHub Fine-Grained PAT — read all repos (Token A) |
| `GITHUB_TOKEN_RW_BLUEPRINT` | `~/.config/gateforge/github-tokens.env` | GitHub Fine-Grained PAT — Blueprint read/write (Token B) |
| `GITHUB_TOKEN_RW_CODE` | `~/.config/gateforge/github-tokens.env` | GitHub Fine-Grained PAT — Code repo read/write (Token C) |
| `GATEWAY_AUTH_TOKEN` | `/opt/secrets/gateforge.env` | OpenClaw gateway bearer token |
| `HOOK_TOKEN` | `/opt/secrets/gateforge.env` | OpenClaw hook endpoint bearer token |
| `DEPLOY_HOST` | `/opt/secrets/gateforge.env` | SSH target for deployments (e.g. `user@tonic.<tailnet>.ts.net`) |

There is no `AGENT_SECRET`, no `*_GATEWAY_TOKEN` for peer VMs, no `ARCHITECT_HOOK_TOKEN` (the hook token is just `HOOK_TOKEN`).

---

## Secrets & Token Locations

GateForge separates secrets by owner and lifetime. You MUST read and write tokens only at the locations listed below. Do not create ad-hoc `.env` files elsewhere, and do not inline secrets in commits, prompts, or logs.

| Secret Class | Location | Permissions | Owner |
|---|---|---|---|
| **Platform tokens** (gateway, hook, Tailscale auth) | `/opt/secrets/gateforge.env` | `root:root` · `0600` | Host / systemd only |
| **GitHub tokens** (fine-grained PATs, machine-user tokens) | `~/.config/gateforge/github-tokens.env` | `$USER:$USER` · `0600` | OpenClaw agent user |
| **All other application tokens** (Anthropic, Telegram, Brave Search, 3rd-party SaaS) | `~/.config/gateforge/<app>.env` | `$USER:$USER` · `0600` | OpenClaw agent user |

### Loading order

1. The systemd service for the OpenClaw gateway sources `/opt/secrets/gateforge.env` at start.
2. The agent user's shell profile sources every file under `~/.config/gateforge/*.env`.
3. `openclaw.json` references variables by name (e.g. `${ANTHROPIC_API_KEY}`); resolution follows shell environment first, then the gateway's EnvironmentFile.

### Rules

- **Never print a secret.** Treat any value loaded from these paths as opaque. Do not echo, log, or commit it.
- **Never copy secrets into commits or task descriptions.** Reference them by env-var name only.
- **Never write to `/opt/secrets/gateforge.env`.** It is managed exclusively by `install/setup-single.sh`.
- **When a new third-party token is needed**, request it from the human via Telegram with the proposed filename (`~/.config/gateforge/<app>.env`) and env-var names. Do not invent a location.
