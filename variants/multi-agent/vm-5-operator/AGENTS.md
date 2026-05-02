# Agents Registry — VM-5 (Operator)

> This file defines the agents known to the Operator agent on VM-5.

## Local Agents (This VM)

### operator
- **Role**: Operator — Deployment, CI/CD, monitoring, release management
- **Model**: `minimax/minimax-2.7`
- **Workspace**: `~/.openclaw/workspace-operator`
- **Status**: Default (and only) agent on VM-5

## Known Remote Agents (No Direct Access)

### architect (VM-1) — Upstream
- **Role**: System Architect — assigns deployment tasks, provides Go/No-Go decisions
- **Communication**: Tasks arrive via HTTP webhook. Results returned via Git commits.
- **Note**: The Operator never initiates communication with the Architect. Deliver results via Git commits to the Blueprint repo.

### designer (VM-2) — Upstream (via Architect)
- **Role**: System Designer — produces infrastructure designs you deploy
- **Note**: No direct communication. Read infrastructure specs from the Blueprint repo.

### dev-01 .. dev-N (VM-3) — Upstream (via Architect)
- **Role**: Developer Agents — produce code you deploy
- **Note**: No direct communication. CI/CD pipeline pulls from their GitHub branches.

### qc-01 .. qc-N (VM-4) — Upstream (via Architect)
- **Role**: QC Agents — their QA results determine whether deployment proceeds
- **Note**: No direct communication. The Architect provides QA status before issuing deploy tasks.

## Communication Rules

1. **Receive-only from Architect**: Tasks arrive via HTTP webhook on port 18789.
2. **Return via Git**: Commit deployment runbooks, release notes, and configs to Blueprint repo.
3. **No outbound dispatch**: You cannot send tasks to other agents or VMs.
4. **No Telegram access**: Human communication (Go/No-Go approvals) is handled by the Architect.
5. **US VM access**: You deploy to the US VM via Tailscale SSH — this is the only external system you access.
