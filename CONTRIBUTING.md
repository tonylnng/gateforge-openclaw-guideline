# Contributing to `gateforge-openclaw-guideline`

This repository is the single source of truth for the GateForge Agentic SDLC guideline. Edits here propagate to every GateForge project that pins this repo. Contribute carefully.

---

## Table of Contents

1. [File Authorship Rules — Class A / B / C](#file-authorship-rules--class-a--b--c)
2. [Branching Model](#branching-model)
3. [Versioning](#versioning)
4. [Guideline Pinning Discipline](#guideline-pinning-discipline)
5. [Commit Convention](#commit-convention)
6. [Pull-Request Workflow](#pull-request-workflow)
7. [Adding a New Role Guide](#adding-a-new-role-guide)
8. [Adding an Architecture Decision Record (ADR)](#adding-an-architecture-decision-record-adr)
9. [Adding a New Variant](#adding-a-new-variant)
10. [Pre-Commit Guard](#pre-commit-guard)

---

## File Authorship Rules — Class A / B / C

Every markdown file in the GateForge ecosystem belongs to exactly one of three classes. The agent and operators **MUST** respect this split, otherwise upgrades to the GateForge guideline will require manual merging on every project.

### Class A — OpenClaw Runtime Contract

**Location:** `variants/<variant>/**/{SOUL,AGENTS,USER,TOOLS}.md`, `variants/<variant>/**/openclaw.json`, `variants/<variant>/install/*.sh`

**Rule:** These files describe how the agent is wired into OpenClaw — gateway URLs, sandbox modes, per-VM tokens, hook endpoints. They are **upgraded only by pulling from this repo**. Per-project overrides break future upgrades.

If a project genuinely needs a runtime override, capture it in the project's Class C file and have the operator apply it manually at install time. Never edit Class A files inside a project repo.

### Class B — GateForge Methodology

**Location:** `guideline/BLUEPRINT-GUIDE.md`, `guideline/roles/**/*.md`, `guideline/adaptation/*.md`

**Rule:** Methodology is shared across every project, every variant, every team. Edit upstream (this repo) only. Every change is a SemVer release with a CHANGELOG entry.

### Class C — Project-Specific

**Location:** `project/gateforge_<project_name>.md` inside each project's Blueprint repo (NOT in this repo).

**File-naming convention:** `gateforge_<project_name>.md` where `<project_name>` matches the regex `^[a-z][a-z0-9_]{2,40}$` (snake_case, lowercase, no spaces, no hyphens — to keep project names URL-safe and distinct from kebab-cased methodology files).

**Rule:** When the operator says "start a new project", the agent **MUST**:

1. Ask: *"What is the project name? (snake_case, lowercase, 3–40 chars, e.g. `acme_billing`)"*
2. Validate the answer against `^[a-z][a-z0-9_]{2,40}$`.
3. Copy [`templates/gateforge_PROJECT_TEMPLATE.md`](templates/gateforge_PROJECT_TEMPLATE.md) into the new project's Blueprint repo at `project/gateforge_<name>.md`.
4. Record the path in `project/state.md` as `project_file: project/gateforge_<name>.md`.
5. From that point onward, **all** project decisions, overrides, custom checklists, domain glossaries, stack deviations, compliance notes, and exception cases go into that file — **never** into Class A or Class B files.

**Examples of Class C content:**

- Project glossary (domain-specific terms)
- Stack deviations (e.g. "this project uses Go instead of TypeScript — justification: …")
- Compliance overrides (e.g. "HIPAA additional checks beyond the OWASP baseline")
- Custom quality gates beyond the standard phase-exit checklists
- Project-specific decision notes that aren't ADRs

---

## Branching Model

**Trunk-based development with release tags.**

- All work lands on `main` via short-lived feature branches.
- No `develop` branch. No long-lived release branches.
- Releases are produced by tagging `main`: `git tag -a v2.1.0 -m "..."`.
- Hotfixes for shipped releases use a temporary branch from the tag: `git checkout -b hotfix/v2.0.1 v2.0.0`, fix, merge back to `main`, tag `v2.0.1`.

**Branch naming:**

| Prefix | Purpose | Example |
|---|---|---|
| `feat/` | New methodology section, new role guide, new variant | `feat/add-data-engineering-role` |
| `fix/` | Correctness or behaviour fix | `fix/qc-gate-coverage-target` |
| `docs/` | README, CHANGELOG, CONTRIBUTING | `docs/clarify-pinning-policy` |
| `chore/` | Tooling, scripts, CI | `chore/add-markdown-lint` |
| `hotfix/` | Patch on a tagged release | `hotfix/v2.0.1` |

**Branch lifetime:** ≤ 7 days. If a change cannot land in a week, decompose it.

---

## Versioning

**Semantic Versioning 2.0.0** with GateForge-specific bump triggers:

### MAJOR (`X.0.0`) — methodology re-baseline required

Bump MAJOR when an existing project must take action to remain compliant with the upgraded guideline. Examples:

- A required Blueprint section is added or removed.
- A phase exit-checklist gains a mandatory item that didn't exist before.
- The phase machine itself changes (new phase added, phase removed, transition rules altered).
- A role guide's identity changes (e.g. QA and QC merged into one role).

**Effect on projects:** Every active project that pins the previous MAJOR continues to read from its pinned SHA. Migration is a deliberate operator action, not automatic.

### MINOR (`x.Y.0`) — additive, backwards-compatible

Bump MINOR when:

- A new role guide is added.
- A new optional checklist or section is added.
- A new variant is added.
- An existing checklist gains an optional item.
- A clarifying paragraph or example is added.

**Effect on projects:** Existing projects need do nothing. They opt in by re-pinning when they want the addition.

### PATCH (`x.y.Z`) — non-behavioural

Bump PATCH for:

- Typos.
- Wording clarifications that don't change meaning.
- Broken-link fixes.
- Formatting fixes.

**Effect on projects:** None. Re-pinning is optional.

### Cutting a release

```bash
# 1. Make sure main is green and CHANGELOG is updated
git checkout main && git pull

# 2. Update VERSION
echo "2.1.0" > VERSION
git add VERSION CHANGELOG.md
git commit -m "chore(release): v2.1.0"

# 3. Tag and push
git tag -a v2.1.0 -m "Release v2.1.0 — <one-line summary>"
git push origin main v2.1.0

# 4. Publish a GitHub Release pointing at the tag
gh release create v2.1.0 --title "v2.1.0" --notes-file CHANGELOG.md
```

---

## Guideline Pinning Discipline

Every project's Blueprint repo MUST record which guideline commit it is running against:

```yaml
# In <project>-blueprint/project/state.md
guideline_repo: tonylnng/gateforge-openclaw-guideline
guideline_version: 2.0.0
guideline_commit: 0123456789abcdef0123456789abcdef01234567
```

**Why:** the agent's behaviour must be reproducible. A typo fix in PATCH should not silently change methodology mid-iteration.

**Upgrade flow:**

1. Operator decides to upgrade a project to a new guideline version.
2. Operator messages the agent on Telegram: `Upgrade guideline to v2.1.0 — Approved`.
3. The agent updates `project/state.md` with the new version and commit SHA.
4. The agent commits with `[Ops] Upgrade guideline pin to v2.1.0` and a `GateForge-Phase: OPS` trailer.
5. The agent posts a Telegram acknowledgment with the link to the new SHA.

**Never auto-upgrade.** Agents that hot-pull from `main` will produce non-reproducible results.

---

## Commit Convention

**Conventional Commits 1.0.0** with GateForge phase prefixes when relevant:

```
<type>(<scope>): <subject>

<body>

GateForge-Phase: <PM|DESIGN|DEV|QA|QC|OPS|N/A>
GateForge-Iteration: <number>
GateForge-Status: <Draft|In-Review|Approved>
GateForge-Summary: <one-line for status report>
```

| Type | Use |
|---|---|
| `feat` | New methodology section, new role guide, new variant |
| `fix` | Correctness or behaviour fix |
| `docs` | README, CHANGELOG, CONTRIBUTING (no methodology change) |
| `refactor` | Re-organise without changing meaning |
| `chore` | Tooling, CI, release plumbing |
| `test` | Test fixtures or guard-script tests |

Examples:

```
feat(roles/pm): add cost-envelope checklist to PM exit gate

GateForge-Phase: N/A
GateForge-Status: Approved
GateForge-Summary: PM phase now requires three-lane cost estimate
```

```
fix(variants/multi-agent): correct VM-3 gateway port in AGENTS.md

Was 18789, should be 18789 (no change). Wording was misleading.
GateForge-Phase: N/A
GateForge-Summary: Clarification only, no behaviour change
```

---

## Pull-Request Workflow

1. **Open a PR against `main`** with a clear title following the commit convention.
2. **PR body must include:**
   - What class of change (Class A / B / C — Class C should never appear in this repo).
   - Which SemVer bump it triggers (MAJOR / MINOR / PATCH) and why.
   - Whether it requires a `CHANGELOG.md` entry (almost always yes).
3. **Self-review checklist** (paste into PR body):

```markdown
- [ ] I have updated `CHANGELOG.md` with a `## [unreleased]` entry.
- [ ] My change is the right SemVer bump (MAJOR / MINOR / PATCH).
- [ ] I have not edited any project-specific content (Class C belongs in project repos).
- [ ] All internal links (relative paths between docs) still resolve.
- [ ] If I touched a role guide, I checked it still reads cleanly under both adaptation files.
- [ ] If I touched a Class A file, both variants still install cleanly (`tools/smoke-test.sh` if applicable).
```

4. **Merge** — squash-merge with the PR title as the squash commit subject.
5. **Tag** if the merge completes a release (see [Versioning](#versioning)).

---

## Adding a New Role Guide

If GateForge gains a new phase (e.g. *Data Engineering*, *ML Ops*), follow this checklist:

1. Create `guideline/roles/<phase>/<PHASE>-GUIDE.md` using one of the existing guides as a template.
2. Update `guideline/adaptation/MULTI-AGENT-ADAPTATION.md` and `SINGLE-AGENT-ADAPTATION.md` with the multi-vs-single deltas for the new phase.
3. Update both variants' `SOUL.md` phase-machine table.
4. Update `templates/gateforge_PROJECT_TEMPLATE.md` if the new phase produces project-specific content.
5. Bump MINOR.
6. Add a `CHANGELOG.md` entry under "Added".

---

## Adding an Architecture Decision Record (ADR)

Significant methodology decisions — anything that, six months from now, a reader (human or agent) might ask *"why was this done this way?"* about — are recorded as ADRs under [`docs/adr/`](docs/adr/README.md).

When to write an ADR:

- You're proposing or accepting a change that shapes how every project will work (e.g., new phase model, new review process, new pinning rule).
- You're rejecting a tempting alternative and want the rejection on record so it isn't re-litigated.
- You're superseding a previous ADR.

Workflow:

1. Pick the next sequential number from [`docs/adr/README.md`](docs/adr/README.md). Zero-pad to 4 digits. **Never** reuse, renumber, or delete a number.
2. Copy the template:
   ```bash
   cp templates/ADR-TEMPLATE.md docs/adr/NNNN-kebab-case-title.md
   ```
3. Fill in **Context**, **Decision**, **Consequences**, **Alternatives Considered**, **References**, and **Revision History**. The hardest section is *Alternatives Considered* — do not skip it.
4. Open a PR titled `adr: ADR-NNNN <title>`. Set status to `Proposed` initially.
5. On merge, set status to `Accepted` and add a row to the ADR index in `docs/adr/README.md`.
6. **Bump MINOR** and add a `CHANGELOG.md` entry under "Added".

To supersede an existing ADR:

1. Write the new ADR with the next sequential number; reference the old one in `## 5. References`.
2. In the **old** ADR, change `Status` to `Superseded by ADR-NNNN` and add a Revision History row.
3. Update the index — do **not** delete the old row, just mark its status `Superseded`.

**Class B vs Class C:** ADRs that shape the guideline itself live here (`docs/adr/`, Class B). Project-specific ADRs (e.g. "Project Acme Billing chose Postgres") live in that project's Blueprint repo at `project/adr/` (Class C) and **must not** be committed here.

---

## Adding a New Variant

If GateForge gains a new topology (e.g. *cluster-agent* with auto-scaling Kubernetes pods), follow this checklist:

1. Create `variants/<variant-name>/` with the standard skeleton (README, agent-workspace or per-VM folders, install/, docs/).
2. Reuse `guideline/` unchanged. Do NOT duplicate methodology.
3. Add a new `guideline/adaptation/<VARIANT>-AGENT-ADAPTATION.md` describing how the variant adapts each role guide.
4. Update top-level `README.md` with the new variant in the comparison table.
5. Bump MINOR (additive).

---

## Pre-Commit Guard

This repo ships [`tools/guard-class-ab.sh`](tools/guard-class-ab.sh). It is intended to be installed in **project Blueprint repos** (not this one — every change in this repo is by definition Class A or B). Project repos should run it as a `pre-commit` hook so an over-eager agent cannot smuggle Class A or B content into project state.

To install in a project repo:

```bash
cp /path/to/gateforge-openclaw-guideline/tools/guard-class-ab.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Or wire it into [pre-commit](https://pre-commit.com/) via a project-level `.pre-commit-config.yaml`.

---

## Questions

Open an issue. Use the labels:

- `class-a`, `class-b`, `class-c` for clarification questions about file class.
- `methodology` for questions about a role guide.
- `variant:multi`, `variant:single` for runtime-contract questions.
- `release` for versioning / release-management questions.
