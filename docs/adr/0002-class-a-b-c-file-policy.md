# ADR-0002: Class A / B / C file authorship policy

---

## Metadata

| Field | Value |
|-------|-------|
| **ADR number** | `0002` |
| **Status** | `Accepted` |
| **Date** | `2026-05-02` |
| **Author(s)** | Tony NG |
| **Deciders** | Tony NG |
| **Class** | B (methodology) |
| **Tags** | governance, file-policy, agent-safety |

---

## 1. Context

Once the guideline became a single upstream source pinned by SHA from many downstream project repos (see [ADR-0001](0001-two-layer-architecture.md)), a recurring failure mode appeared: project-specific content leaking into upstream files.

Concrete examples observed before this policy existed:

- An over-eager agent edited `SOUL.md` to add a project-specific glossary term.
- A role guide accumulated a list of "for the Acme project, do X instead" notes.
- An install script grew project-specific environment variables that broke other projects.

Every one of these edits silently broke the upstream→downstream contract. The next project that pinned a newer SHA inherited content that didn't belong to it. Worse, the next time the upstream maintainer wanted to improve the methodology, they had to untangle which lines were generic and which were project-specific.

We need a hard rule that any human or agent can apply *before* writing a single line of markdown.

---

## 2. Decision

We will classify every file in the GateForge ecosystem into exactly one of three classes and forbid cross-class edits.

| Class | What it is | Where it lives | Who edits it |
|-------|-----------|----------------|--------------|
| **A — Runtime contract** | The four files the OpenClaw runtime reads (`SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`), `openclaw.json`, install scripts | `gateforge-openclaw-guideline/variants/<v>/**` | Guideline maintainers only. **Upstream-only.** |
| **B — Methodology** | Blueprint guide, role guides, adaptation files, ADRs | `gateforge-openclaw-guideline/guideline/**` and `gateforge-openclaw-guideline/docs/adr/**` | Guideline maintainers only. **Upstream-only.** |
| **C — Project-specific** | One file per project, capturing all overrides, glossary, stack deviations, exceptions, project ADRs | `<project>-blueprint/project/gateforge_<project_name>.md` and `<project>-blueprint/project/adr/**` | Project operator. **Downstream-only.** |

Hard rules:

1. **A and B never contain project-specific content.** Every project decision goes into Class C, full stop.
2. **C never appears in the guideline repo.** A grep for `gateforge_*.md` (other than the template) in `gateforge-openclaw-guideline` is a CI failure.
3. **A and B are pulled by SHA pin, not edited locally.** A project that needs to override a Class A or B behaviour records the override in its Class C file and applies it manually at install time.
4. **Class C file naming:** `^gateforge_[a-z][a-z0-9_]{2,40}\.md$` — enforced by `tools/bootstrap-project.sh`.
5. **The guard runs as a pre-commit hook in project repos** (`tools/guard-class-ab.sh`) to block any commit that touches a path matching Class A or Class B locations.

---

## 3. Consequences

### Positive

- Upstream methodology fixes are safe to ship — no project-specific content can hide in them.
- A new project's entire customisation surface is one file. Easy to review, easy to migrate, easy to diff.
- Agents have a deterministic answer to "where does this content go?" that doesn't require methodology judgement.
- Audit / handover: any reviewer can answer "what is this project's deviation from standard?" by reading exactly one file.

### Negative

- Operators who want a quick local edit to a role guide must instead record the deviation in their Class C file. Slightly more friction for one-off tweaks.
- The Class C file can grow large in long-running projects. Mitigated by the template's section structure (glossary, stack deviations, exceptions, ADRs as subsections).
- Two enforcement surfaces: CI in the guideline repo (no Class C content) + pre-commit hook in project repos (no Class A/B edits). Both must be kept healthy.

### Neutral

- This policy makes the guideline repo *boring* on purpose — no project flavour, just methodology. That's the goal.

---

## 4. Alternatives Considered

### Alternative A — Free-form, trust-based ("just don't put project stuff upstream")

- **What:** Document the convention in `CONTRIBUTING.md` and trust contributors / agents to follow it.
- **Pros:** Zero tooling.
- **Cons:** Already failed in practice. Agents and humans both forget. By the time leakage is noticed, the SHA is pinned somewhere.
- **Why rejected:** A rule without enforcement is a suggestion. Agents in particular need machine-checkable rules.

### Alternative B — One project = one fork of the guideline repo

- **What:** Each project forks the guideline and edits anything it wants directly.
- **Pros:** Maximum flexibility. No cross-class rules needed.
- **Cons:** Upstream methodology fixes never propagate without manual rebase per project. Defeats the entire purpose of having a shared guideline.
- **Why rejected:** Recreates the original drift problem at a higher scale.

### Alternative C — Two classes only (upstream / project)

- **What:** Collapse Class A and Class B into one "upstream" bucket.
- **Pros:** Simpler mental model.
- **Cons:** Class A (runtime contract) and Class B (methodology) have *different* update cadences and *different* impact when changed. Class A changes can require re-installing VMs. Class B changes are usually wording. Treating them as one class loses important signal.
- **Why rejected:** The cost of one extra class is small. The benefit of distinguishing "runtime contract" from "methodology" shows up in changelog entries, review intensity, and operator guidance.

---

## 5. References

- `CONTRIBUTING.md` § File Authorship Rules — Class A / B / C
- `tools/guard-class-ab.sh` — pre-commit hook for project repos
- `tools/bootstrap-project.sh` — creates the Class C file from template
- `templates/gateforge_PROJECT_TEMPLATE.md` — Class C scaffold
- Related: [ADR-0001](0001-two-layer-architecture.md) (the two-layer repo this policy operates over)

---

## 6. Revision History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-02 | Created and accepted as part of v2.0.0 consolidation | Tony NG |
