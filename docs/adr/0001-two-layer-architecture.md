# ADR-0001: Two-layer architecture — methodology in `guideline/`, runtime contract in `variants/<v>/`

---

## Metadata

| Field | Value |
|-------|-------|
| **ADR number** | `0001` |
| **Status** | `Accepted` |
| **Date** | `2026-05-02` |
| **Author(s)** | Tony NG |
| **Deciders** | Tony NG |
| **Class** | B (methodology) |
| **Tags** | architecture, repo-structure, governance |

---

## 1. Context

Before consolidation, GateForge lived in two repositories:

- `gateforge-openclaw-configs` — multi-agent runtime contract (5 VMs, `SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`, install scripts).
- `gateforge-openclaw-single` — single-agent runtime contract (1 VM, same four files in different shape, plus a phase-machine adaptation).

Both repos **also** carried their own copy of the methodology — Blueprint guide, role guides (PM, system-design, development, QA, QC, operations), SDLC pipeline, and review process. The methodology was ~95% identical between the two, but every wording fix had to be made twice and the copies inevitably drifted.

This created three problems:

1. **Drift.** A clarification landed in one repo and never made it to the other.
2. **Re-baseline cost.** Projects pinning the multi-agent repo could not benefit from a methodology fix made in the single-agent repo without manual back-port.
3. **Cognitive load.** Reading the methodology required picking a variant first, even though the methodology is variant-agnostic by design.

Meanwhile, the parts that *are* genuinely different between variants — peer review vs self-review, HMAC dispatch vs in-process role switch, 5-VM topology vs 1-VM phase machine — kept getting tangled into the methodology files, which made the methodology itself harder to read.

---

## 2. Decision

We will adopt a **two-layer repository** in `gateforge-openclaw-guideline`:

```
gateforge-openclaw-guideline/
├── guideline/                ← Layer 1: methodology (Class B)
│   ├── BLUEPRINT-GUIDE.md
│   ├── adaptation/
│   │   ├── MULTI-AGENT-ADAPTATION.md
│   │   └── SINGLE-AGENT-ADAPTATION.md
│   └── roles/{pm,system-design,development,qa,qc,operations}/*.md
└── variants/                 ← Layer 2: runtime contracts (Class A)
    ├── multi-agent/{SOUL,AGENTS,USER,TOOLS}.md + install/
    └── single-agent/{SOUL,AGENTS,USER,TOOLS}.md
```

Rules:

- **Methodology is shared.** `guideline/**` is read by both variants. There is one canonical copy.
- **Variants own only the runtime contract.** A variant directory contains the four `*.md` files the runtime reads, install scripts, and variant-specific docs — nothing else.
- **Deltas live in `guideline/adaptation/`.** Anything that differs between multi and single is captured in an adaptation file. The role guides and Blueprint guide stay variant-neutral.
- **Cross-references use relative paths.** A variant's `SOUL.md` reading order points at `../../guideline/...` so clones stay self-contained.

---

## 3. Consequences

### Positive

- One place to fix wording, examples, and methodology gaps. No more drift.
- Projects pinning the consolidated repo by SHA get methodology fixes for both variants in a single bump.
- Easier onboarding — readers can study the methodology *once*, then pick a variant.
- Adaptation files force us to be explicit about what *actually* differs between variants. This turned out to be a smaller surface than expected.

### Negative

- A project upgrading from a legacy repo must update its pin (one-time migration cost). Mitigated by tagging both legacy repos `archived-final` so existing pins still work.
- Variant `SOUL.md` files now use relative paths that escape the variant directory (`../../guideline/...`). Anyone hand-copying a variant directory must remember to also bring `guideline/`. Install scripts handle this automatically.
- A reader has to mentally combine "methodology + variant" rather than reading one self-contained repo.

### Neutral

- The repo is larger overall, but each variant *clones* fewer files than before because the methodology is no longer duplicated.

---

## 4. Alternatives Considered

### Alternative A — Keep two separate repositories, sync methodology with a script

- **What:** Continue with `gateforge-openclaw-configs` and `gateforge-openclaw-single`. Write a sync script that copies methodology between them.
- **Pros:** No migration cost for existing pins.
- **Cons:** Sync scripts rot. Drift detected after the fact, not prevented. Two PR queues, two changelogs, two release cadences for the same methodology change.
- **Why rejected:** The drift problem is *the* problem. A script that papers over it without making one canonical source still loses every time someone forgets to run it.

### Alternative B — Single flat repo with no variant directories (one variant only)

- **What:** Pick one variant (e.g. single-agent) as the canonical form. Drop the other.
- **Pros:** Minimal structure. One way to do things.
- **Cons:** The two variants serve genuinely different deployment shapes — multi-agent has separation-of-duties properties (HMAC, peer review, audit trail per VM) that single-agent cannot match, and single-agent has cost / simplicity properties that multi-agent cannot match. Killing one removes a real capability.
- **Why rejected:** Both variants have active use cases. Neither dominates.

### Alternative C — Submodule the methodology into each variant repo

- **What:** Make `gateforge-openclaw-methodology` a separate repo, submodule it into the two existing variant repos.
- **Pros:** Methodology is canonical. Variant repos stay separate.
- **Cons:** Git submodules are notoriously confusing for operators. Pin management gets two layers (variant SHA + methodology SHA). CI complexity grows. Any read of the methodology requires `git submodule update --init --recursive`.
- **Why rejected:** The operator pain of submodules outweighs the benefit. A monorepo with two top-level directories achieves the same logical separation with none of the submodule overhead.

---

## 5. References

- `CONTRIBUTING.md` § File Authorship Rules — Class A/B/C
- `README.md` § Two-Layer Architecture
- Related: [ADR-0002](0002-class-a-b-c-file-policy.md) (file-class policy enforces this layering at the file level), [ADR-0005](0005-multi-vs-single-variant-split.md) (why two variants exist at all)

---

## 6. Revision History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-02 | Created and accepted as part of v2.0.0 consolidation | Tony NG |
