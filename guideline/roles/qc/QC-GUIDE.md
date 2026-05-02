# QC Guide — GateForge Methodology

> **Class B — Methodology.** This guide is variant-agnostic. For how QC work is split (a dedicated QC VM in multi-agent, a role-switch from QA in single-agent), read the active adaptation file:
>
> - Multi-agent: [`../../adaptation/MULTI-AGENT-ADAPTATION.md`](../../adaptation/MULTI-AGENT-ADAPTATION.md)
> - Single-agent: [`../../adaptation/SINGLE-AGENT-ADAPTATION.md`](../../adaptation/SINGLE-AGENT-ADAPTATION.md)
>
> Always re-read [`../qa/QA-FRAMEWORK.md`](../qa/QA-FRAMEWORK.md) before starting QC — execute the test plan as written, not as remembered.


## 1. Mission

Execute the test plan produced in QA, classify every result, and decide whether the build is releasable.

The QC phase succeeds when:

1. Every test in `project/qa/test-plan.md` has a recorded outcome (`pass`, `fail`, `blocked`, `skipped` with reason) in `project/qc/test-runs/<run-id>.md`.
2. Every `fail` has a defect record in `project/qc/defects/`.
3. The release gate verdict is written in `project/qc/gates/<release>.md`.
4. Telegram has received the QC summary and, if the verdict is `Approved`, the user has replied `Approved` to advance to OPS.

## 2. Inputs

- `project/qa/test-plan.md` (read-only — back-transition to QA if it is wrong)
- The build artefact identified by `project/state.md.last_dev_commit`
- `project/blueprint/05-acceptance-criteria.md`
- The Standard Definition of Done in `SOUL.md`

## 3. Test execution workflow

```
1. Pull the build artefact (Docker image, binary, or git SHA)
2. Stand up the test environment (docker compose up in the QC sandbox)
3. Run the test suites in this order:
   a. Static (SAST, lint, type-check, dependency audit)
   b. Unit
   c. Contract
   d. Integration
   e. End-to-end (BDD against acceptance criteria)
   f. Performance smoke
   g. Security smoke (ZAP baseline, SBOM diff)
4. Collect artefacts (logs, screenshots, JUnit XML, coverage)
5. Record outcomes per test
6. Triage failures
7. Write the gate verdict
```

Each step writes to `project/qc/test-runs/<run-id>/<step>.{log,xml,json}`.

## 4. Defect record format

One file per defect under `project/qc/defects/<id>.md`:

```markdown
# DEF-2026-04-29-001

- Status: Open | In-Dev | Verified | Closed | Wont-Fix
- Severity: Blocker | Critical | Major | Minor | Trivial
- Found-in: <test-id>
- Build: <git-sha>
- Reproduces: 1/1, 5/5, flaky 3/10
- Component: <from build plan>
- Owner-phase: DEV (default) | DESIGN | PM

## Steps
1. ...
2. ...

## Expected
...

## Actual
...

## Logs
<links to artefacts>

## Decision
<close-as-wont-fix justification, or pointer to fix commit>
```

Severity rules:

- **Blocker**: prevents any user from completing the primary outcome → release is blocked.
- **Critical**: data loss, security breach, or money loss possible → release is blocked unless mitigated.
- **Major**: degraded experience for a documented user segment → release allowed with a tracked follow-up.
- **Minor / Trivial**: cosmetic, no behaviour impact.

## 5. Release gate

`project/qc/gates/<release>.md` answers four questions:

1. Did **every blocker and critical defect** close, mitigate, or carry an explicit user-approved waiver?
2. Did the test plan achieve its **coverage target** (e.g. ≥ 80 % unit, 100 % acceptance)?
3. Did the **performance smoke** stay within the NFR budgets?
4. Did the **security smoke** report no new high-severity findings?

If all four are yes, verdict is `Approved`. Otherwise `Rejected` with a list of blockers.

## 6. Back-transitions

- **QC → DEV**: defect is a code bug. Most common path. Increment iteration on DEV.
- **QC → DESIGN**: defect class is structural (e.g. missing seam, wrong contract).
- **QC → QA**: test was wrong (false positive or missing precondition).
- **QC → PM**: acceptance criterion does not match user intent.

Each back-transition logs an ADR in `project/decisions/`. After three QC→DEV cycles on the same defect, escalate to the user.

## 7. Self-review checklist

Before transitioning to OPS:

- [ ] Every test in the plan has an outcome.
- [ ] Every `fail` has a defect record.
- [ ] No blocker or critical defect is `Open`.
- [ ] Test artefacts are committed (compressed if > 10 MB).
- [ ] The gate verdict file exists and is signed with the `[QC]` commit prefix.
- [ ] Coverage and performance numbers are pasted into the Telegram summary.

## 8. Telegram summary template

```
QC Phase complete — <codename> build <sha-short>
Tests: <pass>/<total>  Coverage: <pct>%
Blockers: <n>  Critical: <n>  Major: <n>
Perf: p95 = <ms>ms (budget <ms>ms)
Verdict: Approved | Rejected
Reply `Approved` to deploy, or `Reject` with reason to bounce back to DEV.
```

The Telegram-gated `Approved` is **mandatory** for production deploys; staging deploys may proceed without it but must be labelled `staging-only` in the OPS phase.

## 9. Transition to OPS

```
git add project/qc project/state.md
git commit -m "[QC] Build <sha-short> approved for release" \
  -m "GateForge-Phase: QC" \
  -m "GateForge-Iteration: <i>" \
  -m "GateForge-Status: Approved" \
  -m "GateForge-Summary: <one-line>"
git push
```

Update `project/state.md`:

```yaml
phase: OPS
iteration: 0
release_candidate: <sha>
qc_gate: project/qc/gates/<release>.md
```

## 10. Filename compliance

- Test runs: `project/qc/test-runs/<YYYY-MM-DD-HHMM>-<short-sha>/`
- Defects: `DEF-<YYYY-MM-DD>-<NNN>.md`
- Gates: `<release-tag>.md` (e.g. `v0.1.0.md`)
