# Migrating a project from Multi-Agent to Single-Agent

This guide covers the case where a project was started under the multi-agent variant (`gateforge-openclaw-configs`) and the operator wants to continue it under the single-agent variant.

## When to migrate

- Multi-agent overhead (5 VMs, 9 secrets) exceeds the project's needs.
- Per-role model specialisation no longer pays off.
- Project is in a maintenance phase where parallelism does not help.

Do **not** migrate mid-iteration. Wait until the current phase reaches a clean transition point (any forward gate green).

## Pre-flight

1. The project repo (the user's product, not the GateForge configs repo) must be clean: `git status` shows no uncommitted changes on every multi-agent VM.
2. `project/state.md` exists and is consistent across VMs (it should be, because it lives in git).
3. All Telegram approvals up to the current phase are recorded.

## Migration steps

### 1. Snapshot the multi-agent state

On any of the multi-agent VMs:

```bash
cd /path/to/project
git tag -a multi-agent-final -m "Last commit before migration to single-agent"
git push origin multi-agent-final
```

### 2. Provision the single-agent VM

Follow `install/INSTALL-GUIDE.md` to stand up a fresh VM. Do not reuse a multi-agent VM — its sandbox mode and tokens differ.

### 3. Clone the project on the single-agent VM

```bash
cd ~/projects
git clone <project-repo-url>
cd <project>
git checkout multi-agent-final
git checkout -b single-agent
```

### 4. Rewrite `project/state.md`

Open `project/state.md` and:

- Keep `phase`, `iteration`, `codename`, all `last_*_commit` fields.
- **Remove** any per-VM tokens, HMAC nonces, gateway URLs, or notification queues.
- Add `migrated_from: multi-agent` and `migration_date: <YYYY-MM-DD>`.

Commit:

```
git commit -am "[Ops] Migrate state file to single-agent format" \
  -m "GateForge-Phase: <current>" \
  -m "GateForge-Iteration: <i>" \
  -m "GateForge-Status: Hotfix" \
  -m "GateForge-Summary: Migration from multi-agent variant"
```

### 5. Re-load the agent on the new VM

In OpenClaw, point the agent at the single-agent repo's `SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`. Trigger a `/reload` so it picks up the new role guides.

### 6. First action on the single-agent VM

Run a **read-only audit pass** before doing any work:

1. Re-load every role guide.
2. Read `project/state.md` and the most recent commit on each phase.
3. Post a Telegram message: `Migration to single-agent complete. Project at phase <X> iteration <i>. No work performed.`
4. Wait for user `Approved` before resuming the phase machine.

### 7. Decommission the multi-agent VMs

Only after one full SDLC pass succeeds on the single-agent VM:

- Revoke the per-VM `OPENCLAW_TOKEN`s.
- Revoke the gateway `DESIGNER_TOKEN`, `DEV_TOKEN`, `QC_TOKEN`, `OPERATOR_TOKEN`.
- Rotate the HMAC secret to neutralise replayed messages.
- Power down the 4 secondary VMs; keep the architect VM for one cycle as a hot spare.

## Rollback

If the migration fails:

```bash
git checkout multi-agent-final
git push -f origin <branch>:<branch>     # only if no other consumer relies on the new commits
```

Re-spin the multi-agent VMs from their last good snapshots and resume.

## Things you cannot migrate back

The reverse migration (single-agent → multi-agent) is harder because:

- Multi-agent expects per-role token segregation; merging a project that was authored under a single token requires re-signing artefacts.
- Multi-agent's HMAC notification chain expects a continuous history; a gap during single-agent operation has to be back-filled with synthetic notifications.

If you anticipate going back, keep the multi-agent VMs in cold standby and replay history from `multi-agent-final` rather than from the single-agent head.
