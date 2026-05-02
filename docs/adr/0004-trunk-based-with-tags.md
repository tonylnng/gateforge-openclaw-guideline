# ADR-0004: Trunk-based development with release tags

---

## Metadata

| Field | Value |
|-------|-------|
| **ADR number** | `0004` |
| **Status** | `Accepted` |
| **Date** | `2026-05-02` |
| **Author(s)** | Tony NG |
| **Deciders** | Tony NG |
| **Class** | B (methodology) |
| **Tags** | branching, releases, ci |

---

## 1. Context

The guideline repo has a single maintainer-of-record with occasional agent-assisted contributions. Downstream consumers pin by SHA. Releases are tagged with SemVer (see [ADR-0003](0003-semver-policy.md)).

We need a branching model that:

1. Keeps `main` always green and pinnable.
2. Makes the relationship between "what's on main" and "what's released" trivial — no `develop` vs `release` confusion.
3. Allows the maintainer to ship small, frequent updates (typo fixes especially) without ceremony.
4. Doesn't require maintaining long-lived parallel branches for old MAJORs — projects already pin by SHA, so old MAJORs are accessible by tag and don't need a live branch.

Traditional GitFlow (`main` + `develop` + `release/*` + `hotfix/*`) was designed for shipped products that need parallel maintenance branches. A pinned-by-SHA methodology repo doesn't have that need.

---

## 2. Decision

We will use **trunk-based development with release tags**:

- **One long-lived branch:** `main`. It is always shippable.
- **Short-lived feature branches** (`feat/*`, `fix/*`, `docs/*`, `adr/*`) merge into `main` via pull request. Squash or rebase merge — no merge commits in the trunk history.
- **Releases are tags on `main`,** not branches. Tag format: `vMAJOR.MINOR.PATCH` (e.g. `v2.1.0`). Tags are immutable and forward-only.
- **No `develop` branch. No `release/*` branches. No long-lived hotfix branches.**
- **CI runs on every PR and every push to `main`.** Structural sanity checks (Class A/B/C grep, link check, markdown lint) gate merges.
- **Tags are pushed only after CI is green on `main`.** A tag is a deliberate maintainer action.

### Hotfixes

If a critical fix is needed against an *old* MAJOR (e.g., a project pinning `v2.x.x` cannot upgrade to `v3.x.x` yet), the fix is:

1. Cherry-picked or re-applied against the relevant commit.
2. Tagged `vOLD-MAJOR.MINOR.PATCH+1` directly from that commit (detached tag, no branch).
3. Recorded in `CHANGELOG.md` under that MAJOR's section.

This is rare. The default expectation is "upgrade to latest".

---

## 3. Consequences

### Positive

- Trunk history is linear and readable. `git log main` tells the whole story.
- "What's on main" === "what's the latest release candidate". No mental translation.
- Operators always know where to look — there is exactly one branch.
- Agents have a deterministic answer to "where do I open the PR" — always `main`.
- Old releases remain accessible by tag without the cost of maintaining live branches.

### Negative

- A regression on `main` blocks all releases until fixed. We accept this — `main` must be green is the explicit invariant.
- Hotfixing an old MAJOR is slightly awkward (detached tag) but rare enough that we don't optimise for it.
- Multiple in-flight features can step on each other if they touch overlapping files. Mitigated by short-lived branches and small PRs.

### Neutral

- This matches what most modern doc/methodology repos do (Vercel, Cloudflare, Stripe docs all follow trunk-based). No surprise to outside contributors.

---

## 4. Alternatives Considered

### Alternative A — GitFlow (`main` + `develop` + `release/*` + `hotfix/*`)

- **What:** Standard GitFlow as originally described by Vincent Driessen.
- **Pros:** Familiar to teams from product-software backgrounds. Explicit release stabilisation phase.
- **Cons:** Designed for products with long QA cycles. Adds 4 long-lived branches for a methodology repo that ships ~1 page per release. The `develop`-vs-`main` distinction provides zero value when downstream consumers pin by SHA from `main`.
- **Why rejected:** Pure overhead for our shape. A methodology change does not need a stabilisation branch.

### Alternative B — `main` + per-MAJOR branches (e.g. `2.x`, `3.x`)

- **What:** Keep `main` for the latest MAJOR, fork off `2.x`, `3.x` branches when MAJOR bumps happen.
- **Pros:** Easy to ship hotfixes against old MAJORs.
- **Cons:** Old MAJORs are already accessible by tag. The branch adds nothing pins don't already provide. Maintaining N branches for N MAJORs is real ongoing cost.
- **Why rejected:** Tags + cherry-pick handles the rare hotfix case without the standing cost of N branches.

### Alternative C — No branches at all, commit straight to `main`

- **What:** Maintainer pushes directly to `main`. No PR review.
- **Pros:** Lowest possible ceremony.
- **Cons:** No CI gate, no second pair of eyes (even agent-as-second-pair is useful), no PR description for the CHANGELOG and bump rationale.
- **Why rejected:** PR + CI is cheap and catches real mistakes (bad links, accidental Class C content, malformed mermaid). The bar to merge is low — review can be self-review with the checklist — but the gate itself is worth keeping.

---

## 5. References

- `CONTRIBUTING.md` § Branching and § PR Checklist
- `.github/workflows/ci.yml`
- Related: [ADR-0003](0003-semver-policy.md) (the bump rule that determines which tag to push)

---

## 6. Revision History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-02 | Created and accepted as part of v2.0.0 consolidation | Tony NG |
