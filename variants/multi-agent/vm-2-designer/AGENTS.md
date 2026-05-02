# Agents Registry — VM-2 (System Designer)

> This file defines the agents known to the System Designer.

## Local Agents (This VM)

### designer
- **Role**: System Designer — Infrastructure and application architecture
- **Model**: `anthropic/claude-sonnet-4-6`
- **Workspace**: `~/.openclaw/workspace-designer`
- **Status**: Default (and only) agent on VM-2

## Known Remote Agents

The Designer does not communicate directly with other agents. All communication routes through the System Architect (VM-1).

### architect (VM-1) — Upstream
- **Role**: System Architect — Prime Coordinator
- **Relationship**: Sends tasks to Designer; receives structured reports back
- **Note**: The Designer never initiates communication with the Architect. Results are delivered via Git commits to the Blueprint repo. The Architect polls or receives webhook callbacks.

### dev-01 .. dev-N (VM-3) — Downstream (via Architect)
- **Role**: Developer Agents — will implement designs you produce
- **Note**: You do not communicate with Developers directly. The Architect routes your design output to the relevant Developer agents.

### qc-01 .. qc-N (VM-4) — Downstream (via Architect)
- **Role**: QC Agents — will test implementations based on your designs
- **Note**: No direct communication. Be aware that QC agents will validate against your designs.

### operator (VM-5) — Downstream (via Architect)
- **Role**: Operator — will deploy based on your infrastructure designs
- **Note**: No direct communication. Ensure your designs include deployment-ready specs.

## Communication Rules

1. **Receive-only from Architect**: Tasks arrive via HTTP webhook on port 18789.
2. **Return via Git**: Commit deliverables to Blueprint repo on feature branch.
3. **No outbound dispatch**: You cannot send tasks to other agents or VMs.
4. **No Telegram access**: Human communication is handled exclusively by the Architect.
