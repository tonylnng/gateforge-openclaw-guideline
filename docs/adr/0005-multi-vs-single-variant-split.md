# ADR-0005: Keep two runtime variants — `multi-agent` (5-VM) and `single-agent` (1-VM)

---

## Metadata

| Field | Value |
|-------|-------|
| **ADR number** | `0005` |
| **Status** | `Accepted` |
| **Date** | `2026-05-02` |
| **Author(s)** | Tony NG |
| **Deciders** | Tony NG |
| **Class** | B (methodology) |
| **Tags** | architecture, variants, deployment |

---

## 1. Context

GateForge originally shipped as two separate products with overlapping but distinct purposes:

- **multi-agent (5-VM)** — Six SDLC roles (PM, system-design, development, QA, QC, operations) split across five virtual machines, each running its own OpenClaw agent. Inter-VM dispatch over HMAC-signed messages. Peer review across VMs. Designed for environments where separation of duties is a requirement (regulated healthcare, audit-heavy domains).
- **single-agent (1-VM)** — All six roles compressed into a single agent on a single VM, driven by a deterministic phase machine that switches role-identity in-process. Self-review with Telegram backstop. Designed for cost-sensitive or solo-operator deployments where a 5-VM footprint is overkill.

When consolidating into one repo (see [ADR-0001](0001-two-layer-architecture.md)), an obvious question arose: do we need both? Could one variant subsume the other?

The forces:

- **Capability:** multi-agent's separation-of-duties properties (per-VM audit trail, HMAC-signed dispatch, peer review by an independent agent process) are real. They cannot be retrofitted onto single-agent without making single-agent indistinguishable from multi-agent.
- **Cost:** single-agent's 1-VM footprint is ~1/5 the infrastructure spend, plus simpler ops (one set of secrets, one set of logs, one phase machine to reason about). Many real projects don't need separation of duties.
- **Operator preference:** Solo operators and small teams strongly prefer single-agent. Regulated-environment teams strongly prefer multi-agent. There is no overlap zone where one variant is universally better.
- **Methodology overlap:** ~95% of the methodology — Blueprint guide, role guides, SDLC pipeline — applies to both. Only the runtime contract and review/dispatch mechanics differ.

---

## 2. Decision

We will keep **both variants** as first-class citizens, with one shared methodology and two thin runtime contracts:

- `variants/multi-agent/` — 5-VM topology, HMAC dispatch, peer review.
- `variants/single-agent/` — 1-VM topology, in-process phase machine, self-review + Telegram backstop.

Rules for the split:

1. **Methodology is shared.** `guideline/**` is variant-neutral. Role guides describe what each role *does*, not *where it runs*.
2. **Variant deltas live in `guideline/adaptation/`.** `MULTI-AGENT-ADAPTATION.md` and `SINGLE-AGENT-ADAPTATION.md` document exactly the differences — peer review vs self-review, HMAC vs in-process state machine, gateway dispatch vs role-switch.
3. **Each variant has its own `SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`** — these are the runtime contract, by definition variant-specific (Class A).
4. **No "auto-pick" logic.** A project commits to one variant in its Class C file at bootstrap time. Switching variants mid-project is a re-baseline.
5. **Variant choice criteria** are documented in `README.md § Variant Comparison` so operators can pick decisively.

---

## 3. Consequences

### Positive

- Both real use cases (regulated separation of duties, cost-sensitive solo ops) are supported without compromise.
- The 95% shared methodology is genuinely shared — fixing a sentence in `guideline/roles/qa/*.md` improves both variants.
- The 5% that's actually different is *named, scoped, and documented* in adaptation files, not scattered through the methodology.
- Operators have an honest choice. Neither variant is the "default that the other inherits from", so neither has hidden assumptions.

### Negative

- Two install paths to keep working. Mitigated by per-variant install scripts that are short and structurally similar.
- Two runtime contracts to evolve in lock-step when methodology changes affect both. Mitigated by adaptation files surfacing the deltas explicitly.
- Operators must read the variant comparison and pick. Slight onboarding cost, but the comparison table is short and the criteria are usually obvious for any given project.

### Neutral

- A future variant (e.g., 3-VM, or a serverless decomposition) would slot into the same pattern: new directory under `variants/`, new adaptation file, no methodology changes. The split is extensible.

---

## 4. Alternatives Considered

### Alternative A — Single canonical variant (drop one)

- **What:** Pick one variant — likely single-agent, since it covers the larger operator base — and deprecate the other.
- **Pros:** One runtime contract. One install path. Simpler repo.
- **Cons:** Loses separation-of-duties capability that regulated environments require. Multi-agent is not a "fancier single-agent" — it's a different control structure with different audit properties. Killing it removes a real capability.
- **Why rejected:** The two variants serve genuinely different threat models. Cost is not the only axis.

### Alternative B — Single variant with a runtime feature flag

- **What:** One variant directory, one set of `SOUL.md` etc., with conditional logic ("if multi-VM mode, do peer review; else do self-review"). Toggled by config.
- **Pros:** Looks like one product on the surface.
- **Cons:** The conditional logic infects every Class A file. `SOUL.md` becomes "do X if mode=multi else Y" — agents reading it must mentally execute the branch. Agents are not great at consistent conditional behaviour at this layer. And the differences are not just "do X or Y"; they're entire control structures (HMAC dispatch vs in-process state machine).
- **Why rejected:** Conditionals at the SOUL.md layer make agent behaviour less reliable, not more. Two clean variants beat one branchy variant.

### Alternative C — Three or more variants (e.g., add a 3-VM "balanced" variant)

- **What:** Ship multi-agent (5-VM), single-agent (1-VM), and a 3-VM hybrid.
- **Pros:** More choice for the middle of the operator distribution.
- **Cons:** Each variant is real cost — install scripts, adaptation docs, validation, support. We don't have evidence of demand for 3-VM. Premature.
- **Why rejected:** Wait for the demand. The current split is extensible — a third variant can be added cleanly when there's a real customer asking for it.

---

## 5. References

- `README.md` § Variant Comparison
- `guideline/adaptation/MULTI-AGENT-ADAPTATION.md`
- `guideline/adaptation/SINGLE-AGENT-ADAPTATION.md`
- `variants/multi-agent/README.md`, `variants/single-agent/README.md`
- Related: [ADR-0001](0001-two-layer-architecture.md) (the two-layer structure that makes the split clean), [ADR-0002](0002-class-a-b-c-file-policy.md) (variant directories are Class A by definition)

---

## 6. Revision History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-02 | Created and accepted as part of v2.0.0 consolidation | Tony NG |
