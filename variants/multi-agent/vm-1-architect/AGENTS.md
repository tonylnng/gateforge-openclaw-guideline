# Agents Registry — VM-1 (System Architect)

> This file defines the agents known to the System Architect and how to reach them.

## Local Agents (This VM)

### architect
- **Role**: System Architect — Prime Coordinator
- **Model**: `anthropic/claude-opus-4-6`
- **Workspace**: `~/.openclaw/workspace-architect`
- **Channel**: Telegram (primary human interface)
- **Status**: Default agent on VM-1

## Remote Agents (Cross-VM — HTTPS Dispatch via Tailscale Serve)

All cross-VM hosts are addressed by their Tailscale MagicDNS hostname — never by raw 100.x.x.x IP. Each gateway is fronted by `tailscale serve` with an automatic certificate pinned to the MagicDNS name, so dispatch URLs MUST use `https://`.

### designer (VM-2)
- **Role**: System Designer — Infrastructure and application architecture
- **Model**: `anthropic/claude-sonnet-4-6`
- **Gateway**: `https://${VM2_TS_DOMAIN}:18789/hooks/agent` (default `tonic-designer.sailfish-bass.ts.net`)
- **Auth**: `Bearer ${VM2_GATEWAY_TOKEN}`
- **Capabilities**: K8s design, microservice architecture, DB design, security assessment, observability
- **Deliverables**: Infrastructure Design Document, Security Assessment Report, DB Schema

### dev-01 .. dev-N (VM-3)
- **Role**: Developer Agents — Module implementation
- **Model**: `anthropic/claude-sonnet-4-6`
- **Gateway**: `https://${VM3_TS_DOMAIN}:18789/hooks/agent` (default `tonic-developer.sailfish-bass.ts.net`)
- **Auth**: `Bearer ${VM3_GATEWAY_TOKEN}`
- **Capabilities**: Code implementation, unit tests, API documentation, git workflow
- **Deliverables**: Code (GitHub branches), Development Document, API Documentation
- **Note**: Multiple developer agents share VM-3. Address specific agents via `agentId` field (e.g., `dev-01`, `dev-02`).

### qc-01 .. qc-N (VM-4)
- **Role**: QC Agents — Quality assurance, test case design and execution
- **Model**: `minimax/minimax-2.7`
- **Gateway**: `https://${VM4_TS_DOMAIN}:18789/hooks/agent` (default `tonic-qc.sailfish-bass.ts.net`)
- **Auth**: `Bearer ${VM4_GATEWAY_TOKEN}`
- **Capabilities**: Test case generation, API testing, UI testing, performance testing, security testing
- **Deliverables**: QA Framework Document, Test Cases, Test Result Reports
- **Note**: Multiple QC agents share VM-4. Address specific agents via `agentId` field (e.g., `qc-01`, `qc-02`).

### operator (VM-5)
- **Role**: Operator — Deployment, CI/CD, monitoring, release management
- **Model**: `minimax/minimax-2.7`
- **Gateway**: `https://${VM5_TS_DOMAIN}:18789/hooks/agent` (default `tonic-operator.sailfish-bass.ts.net`)
- **Auth**: `Bearer ${VM5_GATEWAY_TOKEN}`
- **Capabilities**: CI/CD pipeline design, deployment (Dev → UAT → Prod), monitoring/alerting, release notes
- **Deliverables**: Deployment Runbook, Release Notes, CI/CD Pipeline Config, Monitoring Dashboard Config
- **Deployment Target**: US VM via Tailscale SSH (`user@tonic.sailfish-bass.ts.net`)

## Network Topology

| VM | Role | Tailscale MagicDNS host | Gateway Port |
|----|------|------------------------|-------------|
| VM-1 | System Architect | `${VM1_TS_DOMAIN}` (default `tonic-architect.sailfish-bass.ts.net`) | :18789 |
| VM-2 | System Designer  | `${VM2_TS_DOMAIN}` (default `tonic-designer.sailfish-bass.ts.net`)  | :18789 |
| VM-3 | Developers       | `${VM3_TS_DOMAIN}` (default `tonic-developer.sailfish-bass.ts.net`) | :18789 |
| VM-4 | QC Agents        | `${VM4_TS_DOMAIN}` (default `tonic-qc.sailfish-bass.ts.net`)        | :18789 |
| VM-5 | Operator         | `${VM5_TS_DOMAIN}` (default `tonic-operator.sailfish-bass.ts.net`)  | :18789 |
| US VM | Deployment Target | `tonic.sailfish-bass.ts.net` | N/A (no OpenClaw) |

Raw Tailscale 100.x.x.x IPs are not used anywhere in this project — the gateways present TLS certs bound to the MagicDNS name only, so dialing the IP fails certificate verification.

## Communication Rules

1. **Hub-and-Spoke**: All communication routes through the Architect. No direct agent-to-agent cross-VM communication.
2. **Cross-VM**: HTTPS POST to `/hooks/agent` on the spoke's MagicDNS host, with `Authorization: Bearer ${VMn_GATEWAY_TOKEN}`.
3. **Intra-VM**: `sessions_send` (only applicable for multi-agent VMs: VM-3 and VM-4).
4. **Results Flow**: Specialists commit outputs to the Blueprint Git repo; the host-side notifier sends an HMAC-signed callback to the Architect's `/hooks/agent` after every push.
