# GateForge Single-Agent — Manual Setup

> **Class A — Runtime contract.** Manual, copy-and-paste setup for the single-agent variant. Companion to [`variants/single-agent/README.md`](../README.md).
>
> **Assumes:** OpenClaw is already installed and running on the target VM, and you know which OS user it runs as.
>
> **Time:** ~15 minutes for a clean run.

---

## Checklist

- [ ] **1.** [Set workspace paths](#1-set-workspace-paths)
- [ ] **2.** [Clone the guideline at a pinned tag](#2-clone-the-guideline-at-a-pinned-tag)
- [ ] **3.** [Copy the agent workspace files](#3-copy-the-agent-workspace-files)
- [ ] **4.** [Create the secrets files](#4-create-the-secrets-files)
- [ ] **5.** [Point OpenClaw at the workspace](#5-point-openclaw-at-the-workspace)
- [ ] **6.** [Create the project Blueprint repo](#6-create-the-project-blueprint-repo)
- [ ] **7.** [Restart and verify](#7-restart-and-verify)

If anything goes wrong or you want to deviate, see the [FAQ](#faq) at the bottom.

---

## File Layout (after setup)

```
HOST VM
│
├── /opt/gateforge/guideline/              ← cloned guideline repo (pinned tag)
│   ├── guideline/                            (Class B — methodology)
│   ├── variants/single-agent/agent-workspace/{SOUL,AGENTS,USER,TOOLS}.md
│   └── docs/adr/
│
├── ~/.openclaw/workspace/                 ← OpenClaw's workspace path
│   ├── SOUL.md   (copies of the four files above)
│   ├── AGENTS.md
│   ├── USER.md
│   └── TOOLS.md
│
├── /opt/secrets/gateforge.env             ← root:root 0600  (platform)
├── ~/.config/gateforge/*.env              ← user:user 0600  (per-app)
│
└── ~/projects/<project>-blueprint/        ← Class C lives here
    └── project/
        ├── state.md                          (pins guideline_commit)
        └── gateforge_<project>.md            (project-specific)
```

The agent reads `SOUL.md` from the workspace, follows relative paths into the cloned guideline, then reads `state.md` and the Class C file from the Blueprint clone.

---

## 1. Set workspace paths

Pick three locations and export them. Every later command uses these.

```bash
export GF_GUIDELINE_DIR="/opt/gateforge/guideline"
export GF_WORKSPACE_DIR="$HOME/.openclaw/workspace"
export GF_PROJECT_ROOT="$HOME/projects"

mkdir -p "$(dirname "$GF_GUIDELINE_DIR")" "$GF_WORKSPACE_DIR" "$GF_PROJECT_ROOT"
```

> Want different paths? See [FAQ → Can I use different directories?](#can-i-use-different-directories)

---

## 2. Clone the guideline

Clone `main`. The working copy on disk just tracks the latest — the agent's *authoritative* pin lives in `state.md` (Step 6), recorded as a commit SHA.

```bash
sudo git clone https://github.com/tonylnng/gateforge-openclaw-guideline.git "$GF_GUIDELINE_DIR"
git -C "$GF_GUIDELINE_DIR" rev-parse HEAD     # ← copy this SHA, you'll paste it in Step 6
```

Verify:

```bash
test -f "$GF_GUIDELINE_DIR/variants/single-agent/agent-workspace/SOUL.md" && echo OK
```

> Want to pin the working copy to a specific tag instead? See [FAQ → Why track `main` in the working copy?](#why-track-main-in-the-working-copy)

---

## 3. Copy the agent workspace files

Copy the four runtime files, then symlink the methodology so the relative paths inside `SOUL.md` resolve.

```bash
# 3a. Copy the four files
cp "$GF_GUIDELINE_DIR/variants/single-agent/agent-workspace/"{SOUL,AGENTS,USER,TOOLS}.md "$GF_WORKSPACE_DIR/"
chmod 0644 "$GF_WORKSPACE_DIR"/*.md

# 3b. Symlink the guideline tree to the position SOUL.md expects (../../guideline)
ln -s "$GF_GUIDELINE_DIR/guideline" "$(cd "$GF_WORKSPACE_DIR/../.." && pwd)/guideline"
```

Verify the relative path resolves:

```bash
test -f "$GF_WORKSPACE_DIR/../../guideline/BLUEPRINT-GUIDE.md" && echo OK
```

---

## 4. Create the secrets files

Two locations: platform secrets (root) and per-app secrets (agent user).

### 4a. Platform secrets — run as root

```bash
sudo install -d -m 0700 -o root -g root /opt/secrets
sudo tee /opt/secrets/gateforge.env >/dev/null <<'EOF'
GATEWAY_AUTH_TOKEN=__REPLACE_ME__
HOOK_TOKEN=__REPLACE_ME__
DEPLOY_HOST=user@host.example
EOF
sudo chmod 0600 /opt/secrets/gateforge.env
sudo "$EDITOR" /opt/secrets/gateforge.env       # replace each __REPLACE_ME__
```

### 4b. Per-app secrets — run as the agent user

```bash
install -d -m 0700 ~/.config/gateforge

cat > ~/.config/gateforge/anthropic.env <<'EOF'
ANTHROPIC_API_KEY=sk-ant-__REPLACE_ME__
EOF

cat > ~/.config/gateforge/github-tokens.env <<'EOF'
GITHUB_TOKEN_READONLY=ghp___REPLACE_ME__
GITHUB_TOKEN_RW_BLUEPRINT=ghp___REPLACE_ME__
GITHUB_TOKEN_RW_CODE=ghp___REPLACE_ME__
EOF

chmod 0600 ~/.config/gateforge/*.env
$EDITOR ~/.config/gateforge/anthropic.env
$EDITOR ~/.config/gateforge/github-tokens.env
```

### 4c. Load the per-app envs into the agent shell

```bash
cat >> ~/.bashrc <<'EOF'

# GateForge — load per-app env files
if [ -d "$HOME/.config/gateforge" ]; then
  for f in "$HOME/.config/gateforge"/*.env; do
    [ -r "$f" ] && set -a && . "$f" && set +a
  done
fi
EOF
. ~/.bashrc

test -n "$ANTHROPIC_API_KEY" && echo "ANTHROPIC_API_KEY loaded (length: ${#ANTHROPIC_API_KEY})"
```

> Need Brave Search, Telegram, or another token? See [FAQ → How do I add another secret?](#how-do-i-add-another-secret)

---

## 5. Point OpenClaw at the workspace

In your OpenClaw configuration:

| Setting | Value |
|---|---|
| Workspace path | `$GF_WORKSPACE_DIR` (the directory from Step 1) |
| Agent ID | `gateforge-single` |
| Default model | `anthropic/claude-sonnet-4-6` |
| Sandbox mode | `all` |
| Tool allowlist | as defined in `TOOLS.md` |

If OpenClaw runs under `systemd`, also wire in the platform secrets:

```bash
sudo systemctl edit openclaw
```

Paste:

```ini
[Service]
EnvironmentFile=/opt/secrets/gateforge.env
```

Then:

```bash
sudo systemctl daemon-reload
```

> Different OpenClaw distribution? See [FAQ → I don't run OpenClaw under systemd](#i-dont-run-openclaw-under-systemd).

---

## 6. Create the project Blueprint repo

One Blueprint repo per project. Only Class C content lives here.

```bash
cd "$GF_PROJECT_ROOT"
git clone https://github.com/<owner>/<project>-blueprint.git
cd <project>-blueprint
mkdir -p project

# 6a. Pin the guideline SHA in state.md
#     This SHA is what the agent treats as authoritative — the working copy on disk
#     can move ahead of it via `git pull`, but the agent reads what is pinned here.
GUIDELINE_SHA=$(git -C "$GF_GUIDELINE_DIR" rev-parse HEAD)
GUIDELINE_DESC=$(git -C "$GF_GUIDELINE_DIR" describe --tags --always)

cat > project/state.md <<EOF
# Project State

| Field | Value |
|---|---|
| **Project name** | <project_name> |
| **Phase** | PM |
| **Iteration** | 0 |
| **Variant** | single-agent |
| **Guideline ref** | ${GUIDELINE_DESC} |
| **Guideline commit (pinned)** | ${GUIDELINE_SHA} |
| **Last updated** | $(date -u +%Y-%m-%dT%H:%M:%SZ) |
EOF

# 6b. Scaffold the Class C file from the upstream template
cp "$GF_GUIDELINE_DIR/templates/gateforge_PROJECT_TEMPLATE.md" \
   project/gateforge_<project_name>.md

# 6c. Install the Class A/B guard as a pre-commit hook
cp "$GF_GUIDELINE_DIR/tools/guard-class-ab.sh" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# 6d. Edit, commit, push
$EDITOR project/gateforge_<project_name>.md
git add project/
git commit -m "chore: bootstrap project — pinned guideline ${GUIDELINE_DESC}"
git push
```

---

## 7. Restart and verify

```bash
sudo systemctl restart openclaw
sudo journalctl -u openclaw -n 200 --no-pager | tail -40
```

The agent should boot and read these in order:

1. `SOUL.md` → `AGENTS.md` → `USER.md` → `TOOLS.md` (workspace)
2. `…/guideline/adaptation/SINGLE-AGENT-ADAPTATION.md`
3. `…/guideline/BLUEPRINT-GUIDE.md`
4. `…/guideline/roles/pm/PM-GUIDE.md` *(because phase = PM)*
5. `<project>-blueprint/project/state.md` and `gateforge_<project>.md`

**Smoke-test message to the agent:** *"Read state.md, report current phase and pinned guideline commit."* — answer should match what you wrote in Step 6a.

If any step in the boot sequence fails, see the [FAQ](#faq).

---

## FAQ

### Can I use different directories?

Yes. Set `GF_GUIDELINE_DIR`, `GF_WORKSPACE_DIR`, and `GF_PROJECT_ROOT` to anything you like in Step 1. Common alternative: drop `/opt` entirely and put everything under `$HOME` (e.g. `GF_GUIDELINE_DIR=$HOME/gateforge-openclaw-guideline`). If you do, drop the `sudo` from Steps 2 and 4a.

### What if I can't create symlinks (Step 3b)?

Edit `SOUL.md` to use absolute paths instead. From your workspace:

```bash
sed -i "s|\.\./\.\./guideline/|$GF_GUIDELINE_DIR/guideline/|g" "$GF_WORKSPACE_DIR/SOUL.md"
```

Trade-off: your workspace `SOUL.md` now diverges from upstream, so on every guideline upgrade you must re-copy the file and re-run the `sed`.

### How do I add another secret?

For an additional per-app token (e.g. Brave Search, Telegram, a third-party SaaS):

```bash
cat > ~/.config/gateforge/<app>.env <<'EOF'
<APP>_API_KEY=__REPLACE_ME__
EOF
chmod 0600 ~/.config/gateforge/<app>.env
$EDITOR ~/.config/gateforge/<app>.env
```

The shell-profile loader from Step 4c picks it up automatically — no other change needed.

For a platform-level secret (loaded by the gateway, not the agent shell), add the line to `/opt/secrets/gateforge.env` and `sudo systemctl restart openclaw`.

### I don't run OpenClaw under systemd

Make the gateway process see `/opt/secrets/gateforge.env` by whatever mechanism your distribution uses:

- **Docker Compose:** `env_file: /opt/secrets/gateforge.env` in the gateway service
- **Wrapper script:** `set -a; . /opt/secrets/gateforge.env; set +a` before launching the gateway
- **Other init systems:** the equivalent of an `EnvironmentFile` directive

The invariant is the same: the gateway process must inherit those env vars at start, without copying their values into a config file.

### Boot fails with "missing file: ../../guideline/…"

The symlink in Step 3b didn't land in the right place. Check:

```bash
ls -la "$(cd "$GF_WORKSPACE_DIR/../.." && pwd)/guideline"
```

You should see a symlink pointing at `$GF_GUIDELINE_DIR/guideline`. If not, redo Step 3b. Alternatively, switch to absolute paths — see *"What if I can't create symlinks"* above.

### Agent can't authenticate to Anthropic

The agent service didn't inherit `ANTHROPIC_API_KEY` from the user shell. Two fixes:

1. Confirm Step 4c ran for the user OpenClaw runs as (not your interactive user, if they're different).
2. Or move `ANTHROPIC_API_KEY` into `/opt/secrets/gateforge.env` and `sudo systemctl restart openclaw` so the gateway loads it via `EnvironmentFile`.

### Agent commits to Blueprint fail with 403

`GITHUB_TOKEN_RW_BLUEPRINT` either isn't set or doesn't grant write access to the Blueprint repo. Confirm with:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: token $GITHUB_TOKEN_RW_BLUEPRINT" \
  https://api.github.com/repos/<owner>/<project>-blueprint
```

`200` means the token can read it. To verify *write* access, attempt a small commit from the agent shell.

### Agent edits a Class A or Class B file anyway

The pre-commit guard from Step 6c isn't installed in the Blueprint clone the agent actually uses, or it's been bypassed with `--no-verify`. Re-run Step 6c. The guard is the last line of defence — `SOUL.md`, the role guides, and the Class A/B/C section in `CONTRIBUTING.md` are the first three.

### Why track `main` in the working copy?

The agent's *authoritative* pin is the commit SHA recorded in `project/state.md`, not whatever happens to be checked out on disk. The working copy under `$GF_GUIDELINE_DIR/` is just the source the agent reads files from — it can sit on `main` and move forward freely without changing agent behaviour, because the agent only treats the pinned SHA as canonical.

This suits a solo operator: `git pull` is your "upgrade", and bumping `state.md` is your deliberate per-project re-pin.

If you'd rather pin the working copy too (multi-operator setup, or you want the on-disk state to match `state.md` exactly), check out a specific tag in Step 2:

```bash
sudo git -C "$GF_GUIDELINE_DIR" fetch --tags
sudo git -C "$GF_GUIDELINE_DIR" checkout v2.2.0
```

Trade-off: every guideline upgrade now requires *two* steps — `git checkout vNEW` on the working copy **and** updating `state.md` in each project. With `main`-tracking, only `state.md` matters.

### How do I upgrade the guideline?

```bash
# 1. Pull the latest guideline into the working copy
sudo git -C "$GF_GUIDELINE_DIR" pull --ff-only

# 2. Re-copy the four workspace files (Step 3a)
cp "$GF_GUIDELINE_DIR/variants/single-agent/agent-workspace/"{SOUL,AGENTS,USER,TOOLS}.md "$GF_WORKSPACE_DIR/"

# 3. For each project you want to upgrade, edit project/state.md:
#      - Guideline ref:    $(git -C "$GF_GUIDELINE_DIR" describe --tags --always)
#      - Guideline commit: $(git -C "$GF_GUIDELINE_DIR" rev-parse HEAD)
#      - Last updated:     <today>
#    Commit and push.

# 4. Restart
sudo systemctl restart openclaw
```

If the upgrade is **MAJOR**, this is a re-baseline — review the migration notes in the new release before committing the pin change. If **MINOR** or **PATCH**, it's safe.

Projects you choose **not** to upgrade are unaffected: they keep reading from their pinned SHA regardless of where the working copy moves.

### Where do project ADRs go?

In the **Blueprint** repo at `<project>-blueprint/project/adr/`, using [`templates/ADR-TEMPLATE.md`](../../../templates/ADR-TEMPLATE.md). They are Class C — never commit them upstream. See [`docs/adr/README.md`](../../../docs/adr/README.md) for the full ADR workflow.

---

> **Where this guide fits:** Class A — runtime contract. Lives in `variants/single-agent/install/`. Updated only when the runtime contract or operator-facing setup changes (MAJOR if procedure becomes incompatible, MINOR if additive, PATCH for wording).
