# Tools Configuration — VM-1 (System Architect)

## Allowed Tools

| Tool | Purpose |
|------|---------|
| `sessions_send` | Send messages to agents within this VM (local only) |
| `sessions_list` | List active sessions |
| `sessions_history` | View session message history |
| `sessions_spawn` | Spawn new agent sessions |
| `session_status` | Check agent session status |
| `memory_search` | Search persistent memory store |
| `memory_get` | Retrieve specific memory entries |
| `read` | Read files from workspace |
| `write` | Write files to workspace |
| `edit` | Edit existing files |
| `exec` | Execute shell commands (full access, no sandbox) |
| `web_search` | Search the web for information |
| `web_fetch` | Fetch content from URLs |
| `git` | Git operations (clone, pull, push, commit, merge) |
| `message` | Send messages via configured channels (Telegram) |
| `lobster` | Invoke Lobster pipeline workflows (YAML-defined) |
| `llm-task` | Structured LLM calls with JSON schema validation |

## Denied Tools

None — the System Architect has full tool access as the prime coordinator.

## Tool Usage Guidelines

### Cross-VM Dispatch

Use `exec` with `curl` to dispatch tasks to remote VMs:

```bash
# Dispatch to Designer (VM-2)
curl -s -X POST https://tonic-designer.sailfish-bass.ts.net:18789/hooks/agent \
  -H "Authorization: Bearer ${DESIGNER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"agentId":"designer","message":"<JSON payload>","sessionKey":"pipeline:<project>:designer"}'
```

### Lobster Pipelines

Use the `lobster` tool for standard SDLC flows:

```bash
# Run full SDLC pipeline
lobster run workflows/gateforge-sdlc.lobster \
  --arg project=gateforge \
  --arg requirements="<text>"

# Run code review loop
lobster run workflows/code-review.lobster \
  --arg project=gateforge \
  --arg blueprint="<text>"
```

### Git Operations

- Commit Blueprint changes with descriptive messages
- Branch naming: `feature/TASK-XXX-short-description`
- Only the Architect merges to `main` / `develop`

### Telegram (Human Interface)

- Report progress summaries to user
- Request Go/No-Go approval for deployments
- Escalate unresolvable conflicts (after 3 retries)

## Sandbox Mode

`sandbox.mode: "off"` — The Architect requires full system access for cross-VM dispatch, git operations, and Lobster execution.

## Environment Variables

Variables are loaded from the files described in **Secrets & Token Locations** below. The table shows which env-var names this VM expects to resolve at runtime and which file owns them.

| Variable | Source File | Purpose |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | `~/.config/gateforge/anthropic.env` | Claude Opus 4.6 API access |
| `TELEGRAM_BOT_TOKEN` | `~/.config/gateforge/telegram.env` | Telegram channel communication |
| `BRAVE_SEARCH_API_KEY` | `~/.config/gateforge/brave.env` | Web search tool provider |
| `GITHUB_TOKEN_READONLY` | `~/.config/gateforge/github-tokens.env` | GitHub Fine-Grained PAT — read-only across all repos (Token A) |
| `GITHUB_TOKEN_RW` | `~/.config/gateforge/github-tokens.env` | GitHub Fine-Grained PAT — read/write to Blueprint repo (Token B) |
| `DESIGNER_TOKEN` | `/opt/secrets/gateforge.env` | Bearer token for dispatching to VM-2 gateway |
| `DEV_TOKEN` | `/opt/secrets/gateforge.env` | Bearer token for dispatching to VM-3 gateway |
| `QC_TOKEN` | `/opt/secrets/gateforge.env` | Bearer token for dispatching to VM-4 gateway |
| `OPERATOR_TOKEN` | `/opt/secrets/gateforge.env` | Bearer token for dispatching to VM-5 gateway |
| `ARCHITECT_HOOK_TOKEN` | `/opt/secrets/gateforge.env` | Bearer token that spokes present when calling the Architect's inbound `/hooks/agent` |
| `VM{2,3,4,5}_AGENT_SECRET` | `/opt/secrets/gateforge.env` | Per-spoke HMAC secrets — used by the Architect to **verify** inbound signatures. Never transmitted. |

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
