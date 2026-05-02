# Agents Registry — Single VM

> Single Agentic SDLC: there is exactly one agent on one VM. This file exists for parity with the multi-agent variant and to make the contrast explicit.

## Local Agents (This VM)

### gateforge-single

- **Role**: Full SDLC agent — assumes PM, Designer, Developer, QA, QC, and Operator roles in sequence
- **Model**: `anthropic/claude-sonnet-4-6` (single model — no fallback to a higher tier needed for any phase)
- **Workspace**: `~/.openclaw/workspace`
- **Channel**: Telegram (primary human interface)
- **Status**: Default (and only) agent on this VM

## Phase Identities

The single agent operates under one of six phase identities at a time. The active phase is always recorded in the Blueprint's `project/state.md`.

| Phase | Identity | Role Guide |
|---|---|---|
| `PM` | Project Manager / Requirements Owner | `roles/pm/PM-GUIDE.md` |
| `DESIGN` | System Designer | `roles/system-design/SYSTEM-DESIGN-GUIDE.md` |
| `DEV` | Developer | `roles/development/DEVELOPMENT-GUIDE.md` |
| `QA` | QA Lead | `roles/qa/QA-FRAMEWORK.md` |
| `QC` | QC Engineer | `roles/qc/QC-GUIDE.md` |
| `OPS` | Operator / SRE | `roles/operations/MONITORING-OPERATIONS-GUIDE.md` |

The agent must read the matching role guide on every phase entry.

## Remote Agents

**None.** This is the principal difference from the multi-agent variant:

- No `designer` on a separate VM
- No `dev-01..N` developer pool
- No `qc-01..N` QC pool
- No `operator` on its own VM
- No hub-and-spoke HTTPS dispatch
- No `gf-notify-architect` host-side service
- No HMAC notification protocol
- No cross-VM `agentId` field — every dispatch is `gateforge-single`

If you are accustomed to the multi-agent flow: imagine the System Architect as a single person doing the whole SDLC themselves, alternating between hat-modes. That's this variant.

## Communication Rules

1. **Single agent**: All work happens in this OpenClaw instance. No outbound dispatch to peer agents.
2. **Telegram is primary**: The agent reports phase entries, blockers, and Go/No-Go requests directly to the operator.
3. **Blueprint is the contract**: Phase transitions, decisions, and status all flow through the Blueprint repo.
4. **No HMAC, no callbacks**: Commits do not trigger external notifications. The agent reads its own commits as state.

## Network Topology

| VM | Role | Tailscale MagicDNS host (default) | Gateway Port |
|---|---|---|---|
| Single VM | All roles | `${SINGLE_TS_DOMAIN}` (default `gateforge-single.<your-tailnet>.ts.net`) | :18789 |
| US VM | Deployment target only | `${DEPLOY_TS_DOMAIN}` (default `tonic.<your-tailnet>.ts.net`) | N/A (no OpenClaw) |

The single VM still uses Tailscale Serve to expose the OpenClaw Control UI over HTTPS, but no peer mesh is needed. If you don't need remote browser access, you can skip Tailscale Serve entirely and bind the gateway to localhost.

## Scaling Up

When a project outgrows this single-agent setup, you can migrate to the multi-agent variant without losing any Blueprint work:

1. Provision the additional 4 VMs per `tonylnng/gateforge-openclaw-configs`
2. Generate per-VM tokens and HMAC secrets via `setup-vm1-architect.sh`
3. The Blueprint repo (already populated by single agent) becomes VM-1's source of truth
4. The single agent's history in `project/decision-log.md` is preserved verbatim

See `docs/MIGRATION-FROM-MULTI-AGENT.md` and the reverse-direction notes in the multi-agent README.
