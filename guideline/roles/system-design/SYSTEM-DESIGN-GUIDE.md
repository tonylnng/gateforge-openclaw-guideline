# System Design Guide — GateForge Methodology

> **Class B — Methodology.** This guide is variant-agnostic. For how the design hand-off behaves under each topology — a network-mediated hand-off in multi-agent, a state-machine transition in single-agent — read the active adaptation file:
>
> - Multi-agent: [`../../adaptation/MULTI-AGENT-ADAPTATION.md`](../../adaptation/MULTI-AGENT-ADAPTATION.md)
> - Single-agent: [`../../adaptation/SINGLE-AGENT-ADAPTATION.md`](../../adaptation/SINGLE-AGENT-ADAPTATION.md)
>
> The deep guide for resilience and security patterns is [`RESILIENCE-SECURITY-GUIDE.md`](RESILIENCE-SECURITY-GUIDE.md) in this same folder.


## 1. Mission

Translate the approved Blueprint into:

1. A **C4 model** (Context → Container → Component) committed under `project/design/c4/`.
2. **Architectural Decision Records** under `project/design/adr/` for every non-trivial choice.
3. **Interface contracts** (OpenAPI, AsyncAPI, gRPC `.proto`, JSON Schema, SQL DDL) under `project/design/contracts/`.
4. A **threat model** under `project/design/threat-model.md` (STRIDE on each container).
5. A **resilience plan** under `project/design/resilience.md` (see deep guide).
6. A **build plan** under `project/design/build-plan.md` — a topologically-sorted list of components the Dev phase will implement.

The DESIGN phase succeeds when `build-plan.md` lists components small enough that each can be implemented and self-tested in a single Dev iteration of fewer than 8 agent-hours.

## 2. Inputs

- `project/blueprint/**` (read-only)
- `project/state.md` (must be `phase: DESIGN`)
- `RESILIENCE-SECURITY-GUIDE.md` (this folder, mandatory reading)
- The agent's tool allowlist in `TOOLS.md`

If any FR or NFR is unclear, **back-transition to PM**. Do not invent requirements.

## 3. C4 model

Use Mermaid `C4Context`, `C4Container`, `C4Component` blocks committed as markdown so the GitHub renderer shows them. One file per level:

- `project/design/c4/01-context.md`
- `project/design/c4/02-containers.md`
- `project/design/c4/03-components.md`
- `project/design/c4/04-code.md` (only for components with non-obvious internal structure)

Every container in level 2 must have at least one ADR justifying its choice (build vs buy, language, runtime, hosting).

## 4. ADR format

One file per decision, named `ADR-<seq>-<slug>.md`. Template:

```markdown
# ADR-007 — Choose PostgreSQL for OLTP store

- Status: Accepted
- Date: 2026-04-29
- Phase: DESIGN
- Iteration: 0
- Supersedes: —
- Superseded-by: —

## Context
<what forced the decision>

## Options
1. PostgreSQL 16
2. MySQL 8
3. SQLite (single-node)

## Decision
PostgreSQL 16 because <2-3 sentences>.

## Consequences
- Positive: <…>
- Negative: <…>
- Neutral: <…>

## Verification
<how a later phase will know this decision held up>
```

## 5. Interface contracts

Every interface that crosses a container boundary needs a machine-readable contract:

| Interface type | File format | Folder |
|---|---|---|
| Synchronous HTTP | OpenAPI 3.1 YAML | `project/design/contracts/openapi/` |
| Async messaging | AsyncAPI 2.6 YAML | `project/design/contracts/asyncapi/` |
| gRPC | `.proto` | `project/design/contracts/proto/` |
| Persisted data | SQL DDL or JSON Schema | `project/design/contracts/data/` |
| CLI | usage page in markdown | `project/design/contracts/cli/` |

The Dev phase generates client and server stubs from these files; do not hand-write request/response shapes.

## 6. Threat model

STRIDE per container, captured in `project/design/threat-model.md`:

| ID | Container | Spoofing | Tampering | Repudiation | Info disclosure | DoS | EoP |
|---|---|---|---|---|---|---|---|

Every cell with a non-trivial risk links to a control in `project/design/resilience.md` or to an ADR.

## 7. Build plan

`project/design/build-plan.md` is the contract with the Dev phase. Format:

```markdown
| # | Component | Depends on | Interfaces | Estimated hours | Test strategy |
|---|---|---|---|---|---|
| 1 | auth.api    | —              | openapi/auth.yaml | 4 | unit + contract |
| 2 | auth.db     | auth.api       | data/auth.sql     | 2 | migration test |
| 3 | auth.worker | auth.api,auth.db | asyncapi/auth.yaml | 6 | unit + integration |
```

Order is execution order. Each row must be independently testable.

## 8. Self-review checklist

Before transitioning to DEV, the agent re-enters the role and verifies:

- [ ] Every Blueprint FR maps to at least one component in `build-plan.md`.
- [ ] Every NFR maps to at least one ADR or resilience control.
- [ ] No component in `build-plan.md` is estimated above 8 hours; if so, decompose.
- [ ] Every container has STRIDE coverage.
- [ ] Every interface contract validates with its tool of record (`openapi-cli validate`, `protoc --proto_path`, `sqlfluff lint`, etc.).
- [ ] All ADRs have status `Accepted`; no `Proposed` ADRs leak into DEV.

## 9. Transition to DEV

```
git add project/design project/state.md
git commit -m "[Design] Build plan ready — <n> components" \
  -m "GateForge-Phase: DESIGN" \
  -m "GateForge-Iteration: <i>" \
  -m "GateForge-Status: Ready-for-Dev" \
  -m "GateForge-Summary: <one-line>"
git push
```

Update `project/state.md`:

```yaml
phase: DEV
iteration: 0
build_plan_components: <n>
last_design_commit: <sha>
```

## 10. Back-transitions

- **DEV → DESIGN**: implementation reveals a missing or wrong contract → revise the contract, regenerate stubs, re-emit the build plan.
- **QA → DESIGN**: test plan exposes an untestable design → add seams, revise components.
- **QC → DESIGN**: a defect class points at a structural flaw, not a bug.
- **OPS → DESIGN**: an SLO breach proves a resilience control is insufficient.

Each back-transition is logged as an ADR with `Supersedes` filled in.

## 11. Filename compliance

Same global rules as PM. Additionally:

- ADR files: `ADR-<NNN>-<kebab-slug>.md` with three-digit sequence.
- C4 files: `<NN>-<level>.md`.
- Contract files inherit the format-specific extension (`.yaml`, `.proto`, `.sql`, `.json`).
