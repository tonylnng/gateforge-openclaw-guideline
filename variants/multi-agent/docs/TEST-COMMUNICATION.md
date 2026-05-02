# test-communication.sh

End-to-end regression test for GateForge agent communication. Run on **VM-1 (Architect)**.

## What it tests

For each selected agent, the script walks through four gates:

| Gate | Meaning | How it's verified |
|---|---|---|
| **A** | Architect → spoke gateway dispatch accepted | `curl -X POST` returns HTTP 200/202 with a `runId` |
| **B** | Spoke agent committed + pushed a file | The prescribed file appears on `origin/<branch>` |
| **C** | Architect received HMAC callback | Architect's hook log contains the task's ID within 90s |
| **D** | Deliverable readable by hub | `git cat-file -e origin/<branch>:<path>` succeeds |

Plus a soft check for the five required commit trailers (`GateForge-Task-Id`, `-Priority`, `-Source-VM`, `-Source-Role`, `-Summary`).

## Menu

```
1) Architect → Designer (VM-2)
2) Architect → Developers (VM-3, N agents 1-by-1)
3) Architect → QC (VM-4, N agents 1-by-1)
4) Architect → Operator (VM-5)
5) All of the above
```

When you pick Developers, QC, or All, it asks how many agents are deployed. The script then iterates `dev-01, dev-02, …` / `qc-01, qc-02, …`.

## Usage

```bash
# Interactive:
sudo ./test-communication.sh

# Non-interactive:
sudo ./test-communication.sh --target designer
sudo ./test-communication.sh --target dev --count 2
sudo ./test-communication.sh --target qc  --count 3
sudo ./test-communication.sh --target operator
sudo ./test-communication.sh --target all --dev-count 2 --qc-count 2

# Keep test branches after the run:
sudo ./test-communication.sh --target all --dev-count 2 --qc-count 2 --no-cleanup
```

## Requirements on VM-1

`/opt/secrets/gateforge.env` (written by `setup-vm1-architect.sh`) must contain:

```
ARCHITECT_HOOK_TOKEN=...
VM2_GATEWAY_TOKEN=...    VM2_AGENT_SECRET=...
VM3_GATEWAY_TOKEN=...    VM3_AGENT_SECRET=...
VM4_GATEWAY_TOKEN=...    VM4_AGENT_SECRET=...
VM5_GATEWAY_TOKEN=...    VM5_AGENT_SECRET=...
```

`GATEWAY_AUTH_TOKEN` is accepted as a fallback gateway token for older installs.

- **Shared config repo cloned at `/opt/gateforge/openclaw-configs/`** — see setup below.
- Tailscale interface up (spoke gateways reachable on port `18789`).
- `curl`, `jq`, `openssl`, `git` installed.

### Shared repo setup (one-time, all VMs)

All pipeline comm tests use `tonylnng/gateforge-openclaw-configs` as the shared
working repo. Test deliverables are committed to the `testing/` folder on
per-agent feature branches. Gate D verifies the pushed file on `origin`.

Clone it once on each VM at the canonical path:

```bash
sudo mkdir -p /opt/gateforge
sudo git clone https://github.com/tonylnng/gateforge-openclaw-configs.git /opt/gateforge/openclaw-configs
sudo chown -R "$USER:$USER" /opt/gateforge/openclaw-configs
```

To use a different location, set `BLUEPRINT_REPO` before invoking the script:

```bash
BLUEPRINT_REPO=/path/to/openclaw-configs ./test-communication.sh --target designer
```

> **Note:** `gateforge-blueprint-template` is a read-only project template — do not use it as the comm-test target repo.

## Flow per agent

```
Architect (this script)
  └─ POST /hooks/agent to spoke gateway  ──────── Gate A
        Payload carries taskId, filename, branch,
        path, commitSubject (all MUST be used verbatim).

Spoke OpenClaw agent
  ├─ writes file at prescribed path
  ├─ commits with 5 required trailers
  └─ git push origin <branch>  ──────── Gate B

Spoke host (systemd path unit)
  └─ gf-notify-architect.sh
        HMAC-SHA256(payload, AGENT_SECRET)
        POST to Architect /hooks/agent  ──────── Gate C

Architect
  └─ verifies HMAC, logs task ID to hook log
  └─ script reads Git to confirm file   ──────── Gate D
```

## Cleanup

By default the script prompts `Delete all TASK-COMMTEST-* branches on origin? [Y/n]`.
Answer **Y** to tidy up. `--no-cleanup` keeps artefacts for forensic inspection.

A standalone cleaner is also shipped:

```bash
sudo ./cleanup-test-branches.sh
```

## Exit codes

- `0` — all selected tests passed (every gate green, or Gate C "skipped" because
  no readable hook log was found and Gate D is green).
- `1` — at least one test failed a mandatory gate.
- `2` — usage error (bad `--target`, missing required flag).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Gate A fails with HTTP 401 | `VM{N}_GATEWAY_TOKEN` doesn't match what the spoke's gateway expects |
| Gate A fails with HTTP 000 | Spoke VM unreachable on Tailscale, or gateway not running |
| Gate B passes but Gate D fails | Agent committed locally but `git push` failed (check spoke's git creds) |
| Gate C always warns "skipped" | No readable Architect hook log; run `journalctl -u openclaw-architect -n 100` manually to check |
| Gate C fails with timeout | Host notifier not installed on spoke, or firewall blocking spoke → Architect :18789 |
| Trailer warnings | Agent's SOUL.md may need re-sync with `install/_SHARED_NOTIFICATION_PROTOCOL.md` |

## Session Key Targeting (important)

Each spoke VM may have multiple active OpenClaw sessions (e.g. a main session, sub-agents, background tasks). Without a `sessionKey` in the dispatch payload, OpenClaw routes the task to **all** active sessions on the VM simultaneously — causing multi-session collision where several sessions each complete the same task and push duplicate commits.

The `dispatch_task` function in `test-communication.sh` now includes `sessionKey` in every payload:

| Role | Session Key |
|------|-------------|
| designer | `pipeline:gateforge:designer` |
| developer | `pipeline:gateforge:dev` |
| qc | `pipeline:gateforge:qc` |
| operator | `pipeline:gateforge:operator` |

Spoke agents MUST be started/configured with these session keys. See `_SHARED_NOTIFICATION_PROTOCOL.md` for the full convention.

**Symptom of missing sessionKey:** Multiple completion reports arrive for the same task; branches appear in the repo that no agent session claims to have created.

## Extending

- Raise `WAIT_GATE_B_SECONDS` (default 90s) via env var for slow LLMs:
  `WAIT_GATE_B_SECONDS=180 sudo -E ./test-communication.sh ...`
- Gateway URLs are built automatically from `VM{2..5}_TS_DOMAIN` and
  `GATEFORGE_PORT` in `/opt/secrets/gateforge.env` as
  `https://<domain>:<port>/hooks/agent`. The gateway runs HTTPS via Tailscale
  Serve — always dial the MagicDNS name, never a raw `100.x.x.x` IP (the
  cert only matches the domain, so IP-based requests fail with a TLS error).
- Override gateway URLs per run if needed (useful when testing a new spoke
  before the env file is updated):
  `DESIGNER_GATEWAY_URL=https://tonic-designer.sailfish-bass.ts.net:18789/hooks/agent sudo -E ./test-communication.sh --target designer`
  (variables: `DESIGNER_GATEWAY_URL`, `DEV_GATEWAY_URL`, `QC_GATEWAY_URL`, `OPERATOR_GATEWAY_URL`)
- Use `--no-cleanup` to leave branches for manual inspection after a failure.
