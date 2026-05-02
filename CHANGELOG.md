# Changelog

All notable changes to the GateForge Agentic SDLC Guideline are documented here.

This project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) with GateForge-specific bump rules — see [`CONTRIBUTING.md` § Versioning](CONTRIBUTING.md#versioning).

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

— No unreleased changes.

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

[Unreleased]: https://github.com/tonylnng/gateforge-openclaw-guideline/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/tonylnng/gateforge-openclaw-guideline/releases/tag/v2.0.0
