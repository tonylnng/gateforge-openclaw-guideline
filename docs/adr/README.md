# Architecture Decision Records (ADRs)

> **Class B — Methodology.** This directory holds the **upstream** ADRs that shape the GateForge guideline itself. Project-specific ADRs live in each project's Blueprint repo at `project/adr/` and are **never** committed here.

---

## What is an ADR?

An **Architecture Decision Record** is a short, dated document that captures *one* significant architectural or methodological decision — *why* it was made, *what* alternatives were considered, and *what* the consequences are.

Format originated with [Michael Nygard's 2011 post](https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions). We use a lightly extended Nygard form — see [`templates/ADR-TEMPLATE.md`](../../templates/ADR-TEMPLATE.md).

## Why we keep ADRs

| Without ADRs | With ADRs |
|---|---|
| "Why did we pick HMAC over mTLS?" — nobody remembers | A dated record with the trade-offs as understood at decision time |
| New engineer (or new agent) re-litigates an old debate | They read the ADR, see it was considered and rejected, move on |
| Decision quietly drifts — code no longer matches intent | Each ADR has a status; superseded ones link to their replacement |
| Audit asks "show me your design rationale" | You hand them `docs/adr/` |
| AI agents hallucinate plausible-but-wrong rewrites | `SOUL.md` can point them at ADRs as authoritative context |

---

## Index

| #    | Title                                                                  | Status   | Date       | Tags |
|------|------------------------------------------------------------------------|----------|------------|------|
| 0001 | [Two-layer architecture: methodology + variants](0001-two-layer-architecture.md) | Accepted | 2026-05-02 | architecture, repo-structure |
| 0002 | [Class A / B / C file authorship policy](0002-class-a-b-c-file-policy.md) | Accepted | 2026-05-02 | governance, file-policy |
| 0003 | [SemVer with GateForge bump triggers](0003-semver-policy.md)            | Accepted | 2026-05-02 | versioning, releases |
| 0004 | [Trunk-based development with tags](0004-trunk-based-with-tags.md)      | Accepted | 2026-05-02 | branching, releases |
| 0005 | [Multi-agent vs single-agent variant split](0005-multi-vs-single-variant-split.md) | Accepted | 2026-05-02 | architecture, variants |

---

## How to write a new ADR

1. **Pick the next number.** Look at the index above and pick `<highest> + 1`. Zero-pad to four digits. **Never** reuse, renumber, or delete a number.
2. **Copy the template:**
   ```bash
   cp templates/ADR-TEMPLATE.md docs/adr/NNNN-kebab-case-title.md
   ```
3. **Fill it in.** Keep it ≤ ~1 page. The hardest section is **Alternatives Considered** — do not skip it. If you skip it, future readers (or agents) will re-litigate the decision.
4. **Open a PR.** Set status to `Proposed`. Title the PR `adr: ADR-NNNN <title>`.
5. **On merge.** Update the ADR's status to `Accepted` in the same PR after deciders sign off, or in a follow-up PR. Add a row to this index.
6. **SemVer bump.** Adding a new ADR is **MINOR** (additive). See [`CONTRIBUTING.md` § Versioning](../../CONTRIBUTING.md#versioning).

## How to supersede an ADR

When a decision is replaced:

1. Write the new ADR with the next sequential number, referencing the old one in `## 5. References`.
2. In the **old** ADR, change `Status` to `Superseded by ADR-NNNN` and add a row to its Revision History.
3. Update this index — do **not** delete the old row, mark its status as `Superseded`.
4. The old ADR stays in place forever. History is the point.

## What belongs here vs in a project repo

| Decision shapes…                          | Lives in                                | Class |
|-------------------------------------------|-----------------------------------------|-------|
| The guideline itself (every project sees it) | `gateforge-openclaw-guideline/docs/adr/` | **B** |
| A single project's stack, domain, exceptions | `<project>-blueprint/project/adr/`      | **C** |

Examples of **Class B** (here):

- "We will separate methodology from runtime contract" (ADR-0001)
- "We will use SemVer with re-baseline = MAJOR" (ADR-0003)
- "We will keep two variants instead of merging into one" (ADR-0005)

Examples of **Class C** (project-side, **not** here):

- "Project Acme Billing will use Postgres over DynamoDB"
- "Project Acme Billing will allow `any` in legacy migration code until phase 5"
- "Project Acme Billing will run on `single-agent` variant, pinned to v2.1.0"

When in doubt: if it's a decision that every future GateForge project would inherit, it's Class B and belongs here. If only one project cares, it's Class C and belongs in that project's Blueprint repo.

---

## Conventions

- **File name:** `NNNN-kebab-case-title.md` (e.g. `0007-hmac-for-inter-vm-auth.md`)
- **Numbering:** zero-padded to 4 digits, sequential, never reused
- **Status values:** `Proposed` · `Accepted` · `Deprecated` · `Superseded by ADR-NNNN`
- **Tone:** decisive. Active voice. Past tense for context, present/imperative for the decision itself.
- **Length:** target one page. If you need more, link out.
- **Edits to accepted ADRs:** allowed only for typo fixes (PATCH bump) or status changes. To change the *decision*, write a new ADR that supersedes it.
