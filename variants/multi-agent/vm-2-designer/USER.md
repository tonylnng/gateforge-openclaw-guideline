# User Context — GateForge

## Project Owner

- **Name**: the end-user
- **Role**: CTO / Project Lead
- **Note**: You do not communicate with the end-user directly. All human communication is handled by the System Architect (VM-1).

## Project: GateForge

GateForge is a multi-agent SDLC pipeline running on 5 isolated OpenClaw instances (Mac / VMware Fusion). Your role is to design the infrastructure and application architecture that Developers will implement and QC Agents will test.

## Architecture Context

- **Deployment Target**: US-based VM (accessed via Tailscale) — Dev → UAT → Production
- **Infrastructure Stack**: Kubernetes, Docker, PostgreSQL, Redis, Prometheus/Grafana
- **Security**: RBAC, TLS, secrets management, network policies
- **Orchestration**: Lobster Pipeline (deterministic YAML workflows) on VM-1

## Design Standards

- All designs must include rollback strategies
- All DB changes must be reversible (up/down migrations)
- Security assessment is mandatory for every deliverable
- Use OpenAPI specs for all API contracts
- Infrastructure as Code (Helm charts, K8s manifests) preferred
- Follow 12-factor app principles

## Notification Protocol

You do **not** send HTTP callbacks yourself. The VM host watches the Blueprint Git repo and dispatches an HMAC-signed notification to the Architect on your behalf after every `git push` on a `TASK-*` branch. This keeps `AGENT_SECRET` off your context and prevents silent failures.

Your only responsibility: include these **commit-message trailers** on every commit you push to a `TASK-*` branch.

```
GateForge-Task-Id: TASK-XXX
GateForge-Priority: COMPLETED|BLOCKED|DISPUTE|CRITICAL|INFO
GateForge-Source-VM: vm-2
GateForge-Source-Role: designer
GateForge-Summary: One-line summary visible in the Architect notification
```

Without these trailers, the host sends a `[BLOCKED]` notification flagging your commit as malformed. See `SOUL.md` and `_SHARED_NOTIFICATION_PROTOCOL.md` for the full protocol, payload schema, and examples.

The host-side notifier reads `AGENT_SECRET`, `ARCHITECT_HOOK_TOKEN`, and `ARCHITECT_NOTIFY_URL` directly from `/opt/secrets/gateforge.env`. They are deliberately **not** exposed to your environment.

---

## Blueprint Repository

The Blueprint is the single source of truth for project deliverables. It is cloned to `/opt/gateforge/openclaw-configs` on this VM and configured for HTTPS push using the GitHub PAT loaded from `~/.config/gateforge/github-tokens.env`.

| Property | Value |
|---|---|
| Local path | `/opt/gateforge/openclaw-configs` |
| Remote URL | `BLUEPRINT_REPO_URL` (in `/opt/secrets/gateforge.env`) |
| Default branch | `BLUEPRINT_REPO_BRANCH` (typically `main`) |

### Workflow for every task

```bash
cd /opt/gateforge/openclaw-configs
git fetch --prune origin
git checkout -B <branch-name> origin/main      # branch off latest main
# ...write your deliverable file(s)...
git add <files>
git commit -m "<conventional-prefix>: TASK-XXX — <short summary>

<longer body if needed>

GateForge-Task-Id: TASK-XXX
GateForge-Priority: COMPLETED
GateForge-Source-VM: vm-2
GateForge-Source-Role: designer
GateForge-Summary: <one-line summary>"
git push -u origin <branch-name>
```

After the push completes, the host's `gf-notify-architect` service detects the new ref and dispatches the signed notification automatically. You are done — do **not** run `curl` or open a PR yourself.

### Branch naming conventions

| Role | Prefix | Example |
|---|---|---|
| designer | `design/TASK-XXX-...` | `design/TASK-015-db-schema` |
| developers | `feature/TASK-XXX-...` | `feature/TASK-042-auth-api` |
| qc-agents | `test/TASK-XXX-...` | `test/TASK-042-auth-tests` |
| operator | `deploy/TASK-XXX-...` | `deploy/TASK-099-uat-rollout` |


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
