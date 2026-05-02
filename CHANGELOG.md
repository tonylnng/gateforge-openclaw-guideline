# Changelog

All notable changes to the GateForge Agentic SDLC Guideline are documented here.

This project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) with GateForge-specific bump rules — see [`CONTRIBUTING.md` § Versioning](CONTRIBUTING.md#versioning).

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

— No unreleased changes.

---

## [2.3.0] — 2026-05-02

### Added

- **Single-agent manual setup guide** — [`variants/single-agent/install/MANUAL-SETUP.md`](variants/single-agent/install/MANUAL-SETUP.md). Class A operator-facing documentation covering the full copy-and-paste procedure for wiring the single-agent variant into an existing OpenClaw installation. Additive only — no runtime contract change, no project re-baseline.
  - 7-step happy path with TL;DR checklist, file-layout diagram, copy blocks, and per-step verification commands.
  - **`main`-tracking working copy** with SHA pinning in `project/state.md` as the authoritative reference — simpler day-to-day upgrades (`git pull` instead of `git checkout vNEW`) while preserving reproducibility through `state.md`.
  - FAQ section absorbing options, troubleshooting, and "what if" content (different directories, no symlinks, additional secrets, non-systemd OpenClaw, common boot failures, upgrade procedure, project ADR location).
- **`variants/single-agent/README.md` § Installation** rewritten as a 7-bullet "at a glance" overview that links into the new `MANUAL-SETUP.md`. The previous inline 6-step block (which referenced setup scripts and a Telegram bootstrap layout) is removed.

### Changed

— None. The runtime contract (`SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`) is unchanged. Only operator-facing setup documentation has been added or restructured.

---

## [2.2.0] — 2026-05-02

### Added

- **Architecture Decision Records (ADRs)** — additive Class B documentation. No methodology change, no project re-baseline.
  - `templates/ADR-TEMPLATE.md` — Nygard-style ADR template with Context / Decision / Consequences / Alternatives Considered / References / Revision History sections, ready to copy for new methodology ADRs (`docs/adr/`) or project ADRs (`<project>-blueprint/project/adr/`).
  - `docs/adr/README.md` — ADR index, write/supersede workflow, Class B vs Class C guidance, naming and numbering conventions.
  - `docs/adr/0001-two-layer-architecture.md` — records the methodology-vs-runtime-contract split.
  - `docs/adr/0002-class-a-b-c-file-policy.md` — records the upstream-only / project-only file authorship rule.
  - `docs/adr/0003-semver-policy.md` — records GateForge-specific SemVer bump triggers.
  - `docs/adr/0004-trunk-based-with-tags.md` — records the branching model.
  - `docs/adr/0005-multi-vs-single-variant-split.md` — records why both variants are kept.
- `README.md`: new **Architecture Decisions** section linking to the ADR index.
- `CONTRIBUTING.md`: ADR workflow added to the contribution flow; new ADRs are MINOR bumps.

### Changed

— None. ADR additions are pure documentation; no Class A or methodology body has been touched.

---

## [2.1.0] — 2026-05-02

### Added

- **Visual presentation upgrade** across the repo, in the same diagrammatic style as the legacy single-agent README. Additive only — every methodology body is unchanged. No behavioural change, no project re-baseline.
  - `README.md`: layered-architecture diagram (Methodology / Runtime / Project), variant-comparison table, repo-layout tree with class annotations, two-layer architecture diagram, file-class summary table, mermaid phase machine, forward-transition guards table, variant-pick decision tree, industry-standards table.
  - `guideline/BLUEPRINT-GUIDE.md`: prepended a **Visual Overview** section — SDLC pipeline ASCII diagram, Blueprint contents box, mermaid Blueprint-bootstrap flow, quality-gates table.
  - `guideline/adaptation/MULTI-AGENT-ADAPTATION.md`: hub-spoke topology diagram, role→VM mapping table, mermaid dispatch sequence, multi-agent translation table, wire-format box, two-pass review diagram, mermaid conflict-resolution flow.
  - `guideline/adaptation/SINGLE-AGENT-ADAPTATION.md`: single-VM topology diagram, role→identity mapping table, mermaid phase machine + forward-transition guards table, single-agent translation table, hand-off recipe box, self-review + Telegram backstop diagram, mermaid conflict flow.
  - `variants/multi-agent/README.md`: variant comparison table, ASCII topology, VM-assignments table, reading-order diagram, mermaid dispatch sequence, repo-layout tree, two-pass review diagram, migration diagram.
  - `variants/single-agent/README.md`: variant comparison table, ASCII topology, phase-state table + mermaid state diagram, forward-transition guards table, reading-order diagram, repo-layout tree, workspace-copy diagram, secrets-layout diagram, mermaid project-bootstrap flow, migration diagram.

### Changed

- Bumped `VERSION` to `2.1.0`.

### Notes

- This is a **MINOR** release per [`CONTRIBUTING.md` § Versioning](CONTRIBUTING.md#versioning): additive presentation, backwards-compatible. Existing projects pinned to `v2.0.0` need do nothing. Re-pinning is optional.

---

## [2.0.0] — 2026-05-02

### Changed (BREAKING)

- **Repository consolidation.** This repo replaces both `tonylnng/gateforge-openclaw-configs` (multi-agent) and `tonylnng/gateforge-openclaw-single` (single-agent), which are now archived. Existing projects MUST update `project/state.md` to set:
  ```yaml
  guideline_repo: tonylnng/gateforge-openclaw-guideline
  guideline_version: 2.0.0
  guideline_commit: <SHA-of-v2.0.0-tag>
  ```
- **Two-layer architecture.** Methodology files now live in [`guideline/`](guideline/) and are shared across every variant. OpenClaw runtime contract files (`SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`) live under [`variants/<variant>/`](variants/) and reference methodology by relative path. Direct edits to runtime files no longer fork the methodology.
- **`SOUL.md` reading order updated** in both variants to point at `../../../guideline/...` instead of carrying duplicated methodology preambles.
- **`adaptation/` files extracted.** The "Single-Agent Adaptation Note" preambles previously prepended to each role guide in the single-agent repo have been consolidated into `guideline/adaptation/SINGLE-AGENT-ADAPTATION.md`. The symmetric `MULTI-AGENT-ADAPTATION.md` documents peer review, HMAC notification, and gateway dispatch.
- **File-class policy formalised.** [`CONTRIBUTING.md`](CONTRIBUTING.md) defines Class A (runtime contract), Class B (methodology), and Class C (project-specific) and forbids Class C content from entering this repo.

### Added

- `templates/gateforge_PROJECT_TEMPLATE.md` — scaffold for the per-project `gateforge_<project_name>.md` file (Class C).
- `tools/guard-class-ab.sh` — pre-commit guard intended for project Blueprint repos to block Class A/B edits in project state.
- `tools/bootstrap-project.sh` — interactive helper that asks for the project name, validates it against the snake_case regex, and creates the project's Class C file from the template.
- Trunk-based branching model with release tags, documented in `CONTRIBUTING.md`.
- SemVer rules with GateForge-specific bump triggers.
- Guideline-pinning discipline (`project/state.md` records `guideline_commit`).

### Removed

- Per-VM duplicates of role guides under `variants/multi-agent/vm-*/`. Each VM folder now contains only its OpenClaw runtime contract files (SOUL/AGENTS/USER/TOOLS + openclaw-config). Methodology lives in `guideline/`.

### Migration Guide

For projects currently pinned to either of the archived repos:

1. Read [`docs/MIGRATION-FROM-LEGACY-REPOS.md`](variants/multi-agent/docs/MIGRATION-FROM-LEGACY-REPOS.md) (or the single-agent equivalent).
2. Update `project/state.md` to point at this repo and the v2.0.0 tag commit.
3. Re-load the agent so it reads the new paths.
4. Run a read-only audit pass before resuming work.
5. Commit `[Ops] Migrate guideline pin to gateforge-openclaw-guideline v2.0.0`.

---

## Pre-2.0.0

Earlier versions lived in `tonylnng/gateforge-openclaw-configs` (multi-agent, v1.0.0) and `tonylnng/gateforge-openclaw-single` (single-agent, v1.0.0). Both repos are archived and read-only as of 2026-05-02. Their full history is preserved at the `archived-final` git tag in each archived repo.

[Unreleased]: https://github.com/tonylnng/gateforge-openclaw-guideline/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/tonylnng/gateforge-openclaw-guideline/releases/tag/v2.1.0
[2.0.0]: https://github.com/tonylnng/gateforge-openclaw-guideline/releases/tag/v2.0.0
