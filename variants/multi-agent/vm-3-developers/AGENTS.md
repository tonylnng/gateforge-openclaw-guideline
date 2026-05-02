# Agents Registry — VM-3 (Developers)

> This file defines the agents known to Developer agents on VM-3.

## Local Agents (This VM)

### dev-01
- **Role**: Developer Agent — Primary developer
- **Model**: `anthropic/claude-sonnet-4-6`
- **Workspace**: `~/.openclaw/workspace-dev-01`
- **Status**: Default agent on VM-3

### dev-02
- **Role**: Developer Agent — Secondary developer
- **Model**: `anthropic/claude-sonnet-4-6`
- **Workspace**: `~/.openclaw/workspace-dev-02`

> Add `dev-03`, `dev-04`, etc. as the team scales.

## Intra-VM Communication

Developers on the same VM can communicate via `sessions_send` for integration coordination:

```
sessions_send(
  sessionKey: "pipeline:gateforge:dev-02:INTEGRATION-001",
  message: "{structured JSON}",
  timeoutSeconds: 120
)
```

Use this only for:
- Integration point alignment between modules
- Shared utility or library coordination
- Conflict resolution on overlapping code areas

## Known Remote Agents (No Direct Access)

### architect (VM-1)
- **Role**: System Architect — assigns tasks, receives reports
- **Communication**: Tasks arrive via HTTP webhook. Results returned via Git commits.
- **Note**: Developers cannot initiate contact with the Architect.

### designer (VM-2)
- **Role**: System Designer — produces infrastructure designs you implement
- **Note**: No direct communication. Read the Designer's output from the Blueprint repo.

### qc-01 .. qc-N (VM-4)
- **Role**: QC Agents — will test your code
- **Note**: No direct communication. Ensure your code is testable and include test requirements in your report.

### operator (VM-5)
- **Role**: Operator — will deploy your code
- **Note**: No direct communication. Follow deployment-friendly practices (Docker, env vars, health checks).
