# ADR-NNNN: <Short, decision-focused title>

> **Class B (methodology)** if filed under `gateforge-openclaw-guideline/docs/adr/`.
> **Class C (project-specific)** if filed under `<project>-blueprint/project/adr/`.
>
> Methodology ADRs shape the guideline itself. Project ADRs capture local decisions (stack picks, domain trade-offs, exceptions). Never mix the two.

---

## Metadata

| Field | Value |
|-------|-------|
| **ADR number** | `NNNN` (zero-padded, sequential, never renumbered) |
| **Title** | `<Short, decision-focused title>` |
| **Status** | `Proposed` \| `Accepted` \| `Deprecated` \| `Superseded by ADR-NNNN` |
| **Date** | `YYYY-MM-DD` |
| **Author(s)** | `<name>` |
| **Deciders** | `<name(s) with authority to accept>` |
| **Class** | `B` (methodology) \| `C` (project) |
| **Tags** | `<comma-separated, e.g. architecture, security, versioning>` |

---

## 1. Context

What is the situation that forces a decision? What are the constraints, requirements, and forces at play? Write so that a reader six months from now — human or AI agent — can understand the world the decision was made in **without having to read other documents first**.

State the problem in 2–5 short paragraphs. Cite specific files, prior ADRs, or external standards where relevant.

---

## 2. Decision

State the decision in **active voice, present tense**:

> *"We will <do X> by <doing Y>, because <key reason>."*

Be specific. A reader should be able to derive the implementation from this section alone. Include code paths, file locations, or commands when they make the decision concrete.

---

## 3. Consequences

What changes after this decision lands? Be honest — every decision has trade-offs.

### Positive

- <Outcome we wanted>
- <Outcome we wanted>

### Negative

- <Cost we accepted>
- <Cost we accepted>

### Neutral

- <Side effect that is neither good nor bad, but worth recording>

---

## 4. Alternatives Considered

For each serious alternative, state **what it was**, **why it was attractive**, and **why it was rejected**. Skipping this section is the most common ADR mistake — future readers re-litigate decisions when the alternatives aren't recorded.

### Alternative A — `<name>`

- **What:** <one-line description>
- **Pros:** <…>
- **Cons:** <…>
- **Why rejected:** <…>

### Alternative B — `<name>`

- **What:** <…>
- **Pros:** <…>
- **Cons:** <…>
- **Why rejected:** <…>

---

## 5. References

- Related ADRs: `ADR-NNNN`, `ADR-NNNN`
- Issues / PRs: `#NN`
- External: <links to RFCs, standards, blog posts, docs>

---

## 6. Revision History

| Date | Change | Author |
|------|--------|--------|
| `YYYY-MM-DD` | Created | `<name>` |
| `YYYY-MM-DD` | Status → Accepted | `<name>` |
| `YYYY-MM-DD` | Superseded by ADR-NNNN | `<name>` |

---

> **How to use this template**
>
> 1. Copy to `docs/adr/NNNN-kebab-case-title.md` (methodology) or `project/adr/NNNN-kebab-case-title.md` (project).
> 2. Replace `NNNN` with the next sequential number — check `docs/adr/README.md` (or `project/adr/README.md`) for the highest existing number. **Never** reuse or renumber.
> 3. Keep the file ≤ ~1 page where possible. If you need more, link out — don't inline.
> 4. Set status to `Proposed` first. Move to `Accepted` only after the deciders sign off (PR review counts).
> 5. **Never delete an ADR.** When superseded, set status to `Superseded by ADR-NNNN` and add a row to the Revision History. The old ADR stays in place so the historical chain is preserved.
