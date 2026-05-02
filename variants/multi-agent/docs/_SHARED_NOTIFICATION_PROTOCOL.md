<!--
  Shared "Notification Protocol (Commit Trailers)" block — replaces the
  previous HMAC-curl section in each spoke's SOUL.md.
  Source of truth: install/_SHARED_NOTIFICATION_PROTOCOL.md
-->

## Notification Protocol

You do NOT send HTTP callbacks. The VM host watches the Blueprint Git repo and dispatches an HMAC-signed notification to the Architect on your behalf after every `git push`. This moves the callback out of your sandbox, keeps `AGENT_SECRET` off the LLM context, and prevents silent failures from forgotten `curl` calls.

Your only responsibility is to include the following **trailers** at the bottom of every commit message on a `TASK-*` branch. Without them, the host will send a `[BLOCKED]` notification flagging your commit as malformed.

### Required trailers (every commit on a TASK-* branch)

```
GateForge-Task-Id: TASK-XXX
GateForge-Priority: COMPLETED|BLOCKED|DISPUTE|CRITICAL|INFO
GateForge-Source-VM: vm-N
GateForge-Source-Role: <your role id>
GateForge-Summary: One-line summary visible in the notification message
```

### Example commit

```
docs: TASK-015 — database schema

Adds up/down migrations and read-replica topology for the orders service.

GateForge-Task-Id: TASK-015
GateForge-Priority: COMPLETED
GateForge-Source-VM: vm-2
GateForge-Source-Role: designer
GateForge-Summary: Database design done. See design/database-schema.md
```

### When to use which priority

| Priority | Use when |
|---|---|
| `COMPLETED` | Task finished, deliverables pushed |
| `BLOCKED` | Cannot continue — open a query file, reference it in Summary |
| `DISPUTE` | Disagree with another agent's output |
| `CRITICAL` | Security issue, infra failure risk, data loss |
| `INFO` | Partial progress, FYI, no action needed |

### What the host does (not your concern, for awareness only)

1. `systemd` path unit detects the updated ref under `.git/refs/heads/`.
2. `gf-notify-architect.sh` reads trailers, loads `AGENT_SECRET` from `/opt/secrets/gateforge.env`, computes `HMAC-SHA256(payload, secret)`, and POSTs to the Architect's `/hooks/agent`.
3. The Architect validates signature + timestamp (unchanged from the original protocol) and processes the notification.

You never run `curl`. You do not need `AGENT_SECRET`, `ARCHITECT_HOOK_TOKEN`, or `ARCHITECT_NOTIFY_URL` in your environment.

### Session Key Convention

Each spoke VM runs OpenClaw with a fixed **session key** that the Architect must use when dispatching tasks. This prevents multi-session collision — a situation where multiple active sessions on the same VM each receive and execute the same task independently, producing duplicate commits and reports.

| VM | Role | Session Key |
|---|---|---|
| VM-2 | designer | `pipeline:gateforge:designer` |
| VM-3 | developer | `pipeline:gateforge:dev` |
| VM-4 | qc | `pipeline:gateforge:qc` |
| VM-5 | operator | `pipeline:gateforge:operator` |

The Architect's `dispatch_task` MUST include the `sessionKey` field in every webhook payload. Without it, OpenClaw routes the task to **all** active sessions on the VM.

**Correct dispatch payload (example for VM-2):**
```json
{
  "agentId": "designer",
  "sessionKey": "pipeline:gateforge:designer",
  "name": "comm-test-task",
  "message": "...",
  "metadata": { ... }
}
```

**If you receive a task without a sessionKey**, process it normally but include an `[INFO]` trailer in your commit summary noting the omission, so the Architect can update the dispatch config.
