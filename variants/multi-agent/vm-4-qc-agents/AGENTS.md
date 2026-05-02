# Agents Registry — VM-4 (QC Agents)

> This file defines the agents known to QC agents on VM-4.

## Local Agents (This VM)

### qc-01
- **Role**: QC Agent — Primary QA agent
- **Model**: `minimax/minimax-2.7`
- **Workspace**: `~/.openclaw/workspace-qc-01`
- **Status**: Default agent on VM-4

### qc-02
- **Role**: QC Agent — Secondary QA agent
- **Model**: `minimax/minimax-2.7`
- **Workspace**: `~/.openclaw/workspace-qc-02`

> Add `qc-03`, `qc-04`, etc. as the team scales.

## Intra-VM Communication

QC agents on the same VM can communicate via `sessions_send` for test coordination:

```
sessions_send(
  sessionKey: "pipeline:gateforge:qc-02:COORDINATION-001",
  message: "{structured JSON}",
  timeoutSeconds: 120
)
```

Use this only for:
- Coordinating test scope to avoid duplication
- Sharing test fixtures or setup scripts
- Reporting shared infrastructure issues

## Known Remote Agents (No Direct Access)

### architect (VM-1)
- **Role**: System Architect — assigns test tasks, receives QA reports
- **Communication**: Tasks arrive via HTTP webhook. Results returned via Git commits.
- **Note**: QC agents cannot initiate contact with the Architect.

### designer (VM-2)
- **Role**: System Designer — designs you validate against
- **Note**: No direct communication. Read designs from the Blueprint repo.

### dev-01 .. dev-N (VM-3)
- **Role**: Developer Agents — wrote the code you are testing
- **Note**: No direct communication. Report defects in your structured report; the Architect routes fixes back to Developers.

### operator (VM-5)
- **Role**: Operator — deploys code after QA passes
- **Note**: No direct communication. Your QA results determine whether deployment proceeds.
