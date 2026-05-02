# ADR-0003: SemVer with GateForge-specific bump triggers

---

## Metadata

| Field | Value |
|-------|-------|
| **ADR number** | `0003` |
| **Status** | `Accepted` |
| **Date** | `2026-05-02` |
| **Author(s)** | Tony NG |
| **Deciders** | Tony NG |
| **Class** | B (methodology) |
| **Tags** | versioning, releases, governance |

---

## 1. Context

The guideline repo is consumed by downstream project repos via a pinned SHA recorded in each project's `state.md`. This pinning model only works if downstream operators can predict, from a version bump alone, **what they have to do** to upgrade.

Standard SemVer ([semver.org](https://semver.org/spec/v2.0.0.html)) is defined for software *APIs*: MAJOR = breaking, MINOR = additive backwards-compatible, PATCH = bug fix. The guideline is not an API — it's a methodology contract — so we need to define what "breaking" means for a methodology.

Concrete signals that should bump differently:

- Renaming a phase in the phase machine vs. fixing a typo in a phase description.
- Adding a new role guide vs. removing a step from an existing role guide.
- Restructuring the repo layout vs. clarifying a sentence in the Blueprint guide.

Without a clear bump rule, every change becomes an argument. With one, the rule decides.

---

## 2. Decision

We will follow **Semantic Versioning 2.0.0** with the following GateForge-specific bump triggers, documented in `CONTRIBUTING.md § Versioning`:

### MAJOR (`X.0.0`) — methodology re-baseline required

Bump MAJOR when an existing project pinning the previous MAJOR **must take action** to remain compliant. Examples:

- A phase is removed, renamed, or its forward-transition guards change.
- A Class A file's contract changes shape (e.g., `SOUL.md` reading order is restructured).
- A role's responsibilities are split, merged, or removed.
- The repo layout moves files projects depend on by relative path.

**Effect on projects:** Each active project keeps reading from its pinned SHA — pins are immutable. Migration to the new MAJOR is a deliberate operator action with re-baseline checklist, never automatic.

### MINOR (`x.Y.0`) — additive, backwards-compatible

Bump MINOR when:

- A new section, role guide, ADR, or template is added.
- An existing section is expanded with new sub-sections, examples, diagrams.
- A new variant is introduced.
- Optional new tooling is added under `tools/`.

**Effect on projects:** A project may upgrade its pin to gain the new content but is not required to.

### PATCH (`x.y.Z`) — non-behavioural

Bump PATCH for:

- Wording fixes, typos, grammar.
- Clarifying examples that do not change meaning.
- Internal repo housekeeping (CI, formatting, comments).

**Effect on projects:** Safe to upgrade pin freely. By the rule, no methodology meaning has changed.

### Guarantees

1. **Pins are immutable.** A SHA pinned by a project never changes meaning. Tags are forward-only — `v2.1.0` always points at the same commit forever.
2. **Re-baseline is operator-initiated, never silent.** The agent's behaviour must be reproducible. A typo fix in PATCH must not silently change methodology mid-iteration.
3. **CHANGELOG entries name the class.** Every entry says which class of change (A / B / C — though C should never appear here) and which bump it triggered.

---

## 3. Consequences

### Positive

- Operators reading a CHANGELOG can decide in seconds whether an upgrade requires a re-baseline.
- A MAJOR bump becomes an honest signal — readers know to slow down.
- Agents reading the CHANGELOG can distinguish wording fixes (safe) from methodology changes (require human approval).
- Disputes about "is this MINOR or PATCH" reduce to "does it change meaning" — not subjective.

### Negative

- We will sometimes bump MAJOR for what looks like a small change (e.g., renaming a phase). The rule trades off "version number inflation" for "honest signal".
- Authors must think about bump class *while* writing the change, not after. PR template enforces this with a checkbox.
- A project that wants the latest typo fix but is pinned to an old MAJOR has to either stay pinned or re-baseline. There is no cherry-pick model.

### Neutral

- Tools that consume CHANGELOG (release notes, dashboards) work without modification — Keep a Changelog 1.1.0 format is preserved.

---

## 4. Alternatives Considered

### Alternative A — CalVer (`YYYY.MM.PATCH`)

- **What:** Use calendar versioning, e.g. `2026.05.0`.
- **Pros:** No semantic judgement required. Always monotonic. Easy to read "how old is this".
- **Cons:** Provides zero signal about *whether* an upgrade is breaking. A project pinning `2026.04.0` cannot tell from the version alone whether `2026.05.0` requires a re-baseline.
- **Why rejected:** The whole point of the bump rule is to encode "do I need to re-baseline?" in the version. CalVer drops that signal.

### Alternative B — Plain SemVer with no GateForge-specific triggers

- **What:** Use SemVer as defined upstream and let contributors interpret "breaking" however they like.
- **Pros:** Familiar.
- **Cons:** "Breaking" is ill-defined for a methodology. Every PR ends in an argument about whether removing a phase is breaking (yes) or whether reordering review steps is breaking (sometimes).
- **Why rejected:** Without our domain-specific triggers, the bump rule produces inconsistent results across maintainers and across time.

### Alternative C — Date-pinned, no version numbers

- **What:** Drop tags. Pin only by commit SHA + commit date.
- **Pros:** Maximally honest — every commit is its own thing.
- **Cons:** Operators lose the human-readable "v2.1.0" handle. Release notes become hard to communicate. Audit trails become hard to read.
- **Why rejected:** Tags are cheap and humans need handles. SHA pins remain authoritative; tags are a UX layer on top.

---

## 5. References

- `CONTRIBUTING.md` § Versioning
- `CHANGELOG.md`
- [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)
- [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/)
- Related: [ADR-0004](0004-trunk-based-with-tags.md) (the branching model that produces these tags)

---

## 6. Revision History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-02 | Created and accepted as part of v2.0.0 consolidation | Tony NG |
