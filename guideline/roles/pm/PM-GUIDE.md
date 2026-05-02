# PM Guide — GateForge Methodology

> **Class B — Methodology.** This guide is variant-agnostic. For variant-specific deltas (peer review vs self-review, HMAC dispatch vs in-process state transition), read the active adaptation file:
>
> - Multi-agent: [`../../adaptation/MULTI-AGENT-ADAPTATION.md`](../../adaptation/MULTI-AGENT-ADAPTATION.md)
> - Single-agent: [`../../adaptation/SINGLE-AGENT-ADAPTATION.md`](../../adaptation/SINGLE-AGENT-ADAPTATION.md)
>
> Always read this guide together with `BLUEPRINT-GUIDE.md` and your variant's `SOUL.md` before doing PM work.


## 1. Mission

Translate a fuzzy human request into a structured, testable, production-ready Blueprint that every later phase (Design → Dev → QA → QC → Ops) can execute against without further clarification.

The PM phase succeeds when:

1. `project/blueprint/` follows the `gateforge-blueprint-template` structure.
2. Every requirement has an ID, a priority, and an acceptance criterion.
3. `project/state.md` is initialised with `phase: PM`, `iteration: 0`, and a project codename.
4. The Telegram channel has received the Blueprint summary and the user has replied `Approved`.

Until all four conditions hold, **the agent must not transition to `DESIGN`**.

## 2. Inputs

| Input | Source | Required? |
|---|---|---|
| User intent | Telegram message, GitHub issue, or `examples/new-project-bootstrap.md` answers | Yes |
| Constraints | User-supplied (deadline, budget, stack preferences) | Optional |
| Existing assets | Linked repos, Figma files, prior Blueprints | Optional |
| Compliance regime | Industry (fintech, health, gov) | Auto-derived if not given |

If any **required** input is missing, ask one consolidated question on Telegram. Do not start drafting until you have an answer.

## 3. PM Workflow

```
        ┌─────────────────────────────────────┐
        │  1. Discovery (Telegram Q&A)        │
        ├─────────────────────────────────────┤
        │  2. Draft Blueprint v0              │
        ├─────────────────────────────────────┤
        │  3. Self-review against IEEE 830    │
        │     + ISO 25010 quality attributes  │
        ├─────────────────────────────────────┤
        │  4. Risk register + cost estimate   │
        ├─────────────────────────────────────┤
        │  5. Send Telegram summary           │
        ├─────────────────────────────────────┤
        │  6. Wait for `Approved`             │
        ├─────────────────────────────────────┤
        │  7. Commit, transition to DESIGN    │
        └─────────────────────────────────────┘
```

### Step 1 — Discovery

Open one Telegram thread per project. Ask **at most three** questions in the first round:

1. What is the primary user outcome?
2. What is the success metric and who measures it?
3. What is the hard deadline or launch event, if any?

Follow-ups (stack, hosting, budget) only if the answers do not reveal them.

### Step 2 — Draft

Use the Blueprint template. Required files in `project/blueprint/`:

- `01-vision.md`
- `02-stakeholders.md`
- `03-scope.md` (in/out)
- `04-requirements/functional.md`
- `04-requirements/non-functional.md` (with the seven ISO 25010 attributes)
- `05-acceptance-criteria.md` (BDD-style, one per FR)
- `06-risks.md`
- `07-glossary.md`

Each functional requirement uses the ID format `FR-<area>-<n>` (e.g. `FR-AUTH-3`). Non-functional uses `NFR-<attribute>-<n>`.

### Step 3 — Self-review checklist

The agent re-enters the role by re-reading this guide and runs the IEEE 830 + ISO 25010 checklist:

- [ ] Every FR is **correct, unambiguous, complete, consistent, ranked, verifiable, modifiable, traceable**.
- [ ] All seven ISO 25010 attributes have at least one NFR or an explicit "N/A — justification".
- [ ] No requirement uses the words "should support", "etc.", "and/or", "as appropriate".
- [ ] Every acceptance criterion is testable in fewer than 30 minutes of manual QC effort.
- [ ] The risk register has at least one risk per requirement area.

Failures are fixed in-place; do not advance with known checklist gaps.

### Step 4 — Risk + cost

Maintain `project/blueprint/06-risks.md`:

| ID | Description | Likelihood | Impact | Mitigation | Owner-phase |
|---|---|---|---|---|---|

Cost estimate goes in `project/blueprint/03-scope.md` under "Cost envelope" with three lanes: optimistic, realistic, pessimistic — in agent-hours and external service spend.

### Step 5 — Telegram summary

Post a single message:

```
PM Phase complete — <codename>
Vision: <1 sentence>
FRs: <n>  NFRs: <n>  Risks: <n>
Estimate: <hours>h  External: $<usd>
Reply `Approved` to start DESIGN, or comment to revise.
```

### Step 6 — Wait

Until the user replies `Approved` (case-sensitive), the agent **must not** advance. Other tasks are allowed but `phase` stays `PM` and the iteration counter increments on each revision.

### Step 7 — Transition

```
git add project/blueprint project/state.md
git commit -m "[PM] Blueprint approved — <codename> v0.1.0" \
  -m "GateForge-Phase: PM" \
  -m "GateForge-Iteration: 0" \
  -m "GateForge-Status: Approved" \
  -m "GateForge-Summary: <one-line>"
git push
```

Update `project/state.md`:

```yaml
phase: DESIGN
iteration: 0
codename: <codename>
last_pm_commit: <sha>
```

## 4. Back-transitions into PM

Other phases may force a return to PM:

- **DESIGN → PM**: requirement is unimplementable as written.
- **DEV → PM**: scope creep discovered.
- **QC → PM**: acceptance criterion is wrong.
- **OPS → PM**: production reveals missing NFR.

Each back-transition increments `project/state.md.iteration`, logs an ADR in `project/decisions/`, and re-runs steps 2–7. After **three** back-transitions on the same project, escalate to the user with a Telegram summary before continuing.

## 5. Artefacts owned by PM

| Path | Lifecycle |
|---|---|
| `project/blueprint/**` | Created in PM, read-only thereafter except via back-transition |
| `project/state.md` | Created in PM, updated by every phase |
| `project/decisions/ADR-PM-*.md` | Created on revisions |
| `project/changelog.md` | Append-only, PM seeds the file |

## 6. Filename compliance

PM artefacts must follow the global filename rules in `SOUL.md` §"Filename compliance":

- All-lowercase except top-level capitalised guides.
- Hyphens, not underscores, in markdown filenames.
- Numeric prefixes (`01-`, `02-`) for ordered Blueprint sections.
- No spaces, no parentheses, no version suffixes (`v2`, `final`, `new`) — those go in commit messages.

## 7. When PM is "good enough"

This is a single-agent SDLC. There is no separate architect to push back. The agent must police itself:

- If a requirement reads like a feature description, rewrite it as a behaviour.
- If a non-functional requirement has no number, add one or delete it.
- If the Blueprint is longer than 60 markdown pages, split scope and ship a smaller v0.1 first.
