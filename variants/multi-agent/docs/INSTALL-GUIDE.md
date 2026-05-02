# GateForge — Step-by-Step Installation Guide

> For users new to Linux. Follow each step exactly as shown.

---

## Before You Start

You need 5 Ubuntu VMs with OpenClaw already installed and working. Each VM should have:
- OpenClaw running with its API key configured
- Telegram configured on VM-1 (Architect)
- Internet access and `sudo` permission

### Required on ALL 5 VMs Before Running Setup Scripts

#### Step A — Gateway Networking (Loopback + Tailscale Serve)

GateForge uses **loopback bind** with **Tailscale Serve** for secure HTTPS access between VMs. The setup scripts configure this automatically, but if you need to do it manually:

```bash
# 1. Bind gateway to loopback only (Tailscale Serve handles external access)
openclaw config set gateway.bind loopback
openclaw config set gateway.tailscale.mode serve
openclaw config set gateway.tailscale.resetOnExit false
openclaw gateway restart

# 2. Start Tailscale Serve (proxies HTTPS :18789 → http://127.0.0.1:18789)
sudo tailscale serve --bg --https 18789 http://127.0.0.1:18789

# 3. Pair your browser/device
openclaw devices list
openclaw devices approve --latest
```

Verify:

```bash
# Gateway should be on loopback
ss -tlnp | grep 18789
# Should show 127.0.0.1:18789

# Tailscale Serve should be running
tailscale serve status

# Access the Control UI via Tailscale domain:
# https://<hostname>.sailfish-bass.ts.net:18789
```

#### Step B — Configure firewall to allow only GateForge VMs

Run this on every VM:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
# Allow all traffic on the Tailscale interface to port 18789.
# This is robust to Tailscale IP changes — only peers on your tailnet can
# reach the interface, and the gateway itself enforces auth (Bearer + HMAC).
sudo ufw allow in on tailscale0 to any port 18789 proto tcp
sudo ufw enable
```

Verify:

```bash
sudo ufw status
```

Only peers on your Tailscale tailnet can reach port 18789 (because `tailscale0` is only attached to tailnet traffic). The gateway itself enforces Bearer-token + HMAC-SHA256 auth, so this is defence-in-depth.

#### Step C — Test connectivity between VMs

From any VM, test that you can reach another VM's gateway:

```bash
curl -s https://tonic-architect.sailfish-bass.ts.net:18789/health
# Should return: {"ok":true,"status":"live"}
```

> Always dial the **Tailscale MagicDNS domain** (`tonic-*.sailfish-bass.ts.net`), never the raw `100.x.x.x` IP. The Tailscale Serve TLS certificate is bound to the MagicDNS hostname, so a raw-IP connection will fail TLS verification.

If this fails, check the bind setting (Step A) and firewall (Step B) on the target VM.

Once all 5 VMs return `{"ok":true,"status":"live"}` from each other, proceed with the setup scripts below.

---

## GitHub Repository Access

GateForge uses multiple private GitHub repositories. Each VM needs authentication to access them.

### GateForge Repositories

| Repository | Purpose | Access |
|-----------|---------|--------|
| `tonylnng/gateforge-openclaw-configs` | Agent configuration (this repo) — SOUL.md, TOOLS.md, install scripts | **Read-only** for all VMs |
| `tonylnng/gateforge-blueprint-template` | Standardised Blueprint document structure — cloned per project, updated over time with improved standards | **Read-only** for all VMs |
| `tonylnng/<project>-blueprint` | Per-project working Blueprint — requirements, architecture, designs, status, backlog | **Read/write** for VM-1 (Architect); read-only for others |
| `tonylnng/<project>-code` | Per-project source code | **Read/write** for VM-3 (Developers) and VM-5 (Operator); read-only for others |
| `tonylnng/gateforge-openclaw-commtest` | Throwaway target repo for `install/test-communication.sh`. Spokes push `TASK-COMMTEST-*` branches here; the test script deletes them after each run. Not used by any project. | **Read/write** for all VMs (VM-1 reads/cleans up; VM-2..5 push test branches) |

### Authentication: Fine-Grained Personal Access Tokens (PATs)

GateForge uses **GitHub Fine-Grained PATs** (not classic tokens) for per-repository and per-permission scoping. See the [GitHub Token Configuration](../README.md#github-token-configuration) section in the main README for the complete setup guide, including:

- **Token A** — Read-only access to all repos (all VMs)
- **Token B** — Read/write access to the project Blueprint repo (VM-1 Architect only)
- **Token C** — Read/write access to the project code repo (VM-3 Developers)
- **Token D** — Read/write CI/CD access to the project code repo (VM-5 Operator)

#### Quick Setup — Clone This Config Repo

On each VM, use the read-only token (Token A) to clone this repo:

```bash
git clone https://<GITHUB_TOKEN_READONLY>@github.com/tonylnng/gateforge-openclaw-configs.git
```

To avoid entering the token on every `git pull`, configure credential storage:

```bash
# Store credentials securely
git config --global credential.helper store
echo "https://gateforge-bot:${GITHUB_TOKEN_READONLY}@github.com" > ~/.git-credentials
chmod 600 ~/.git-credentials
```

For VMs with read/write access (VM-1, VM-3, VM-5), add a URL override for the specific repo:

```bash
# VM-1: read/write override for the project Blueprint repo
git config --global url."https://gateforge-bot:${GITHUB_TOKEN_RW}@github.com/tonylnng/<project>-blueprint".insteadOf \
  "https://github.com/tonylnng/<project>-blueprint"

# VM-3 / VM-5: read/write override for the project code repo
git config --global url."https://gateforge-bot:${GITHUB_TOKEN_RW}@github.com/tonylnng/<project>-code".insteadOf \
  "https://github.com/tonylnng/<project>-code"
```

All tokens are stored in `/opt/secrets/gateforge.env` (root:root, chmod 600). The setup scripts automatically grant read access to the OpenClaw user via POSIX ACL (`setfacl`). See the main README for the full configuration, rotation, and security guide.

> **Note**: The `acl` package must be installed (`sudo apt-get install acl`). The setup scripts detect this and warn if missing. To verify or manually grant access:
>
> ```bash
> # Grant read access to the OpenClaw user
> sudo setfacl -m u:<openclaw-user>:r /opt/secrets/gateforge.env
>
> # Verify the ACL
> getfacl /opt/secrets/gateforge.env
> ```

---

## VM-1: System Architect (run this FIRST)

### Step 1 — Open a terminal on VM-1

Connect to `tonic-architect` via SSH or open a terminal directly:

```bash
ssh user@tonic-architect
```

### Step 2 — Install prerequisites (if not already installed)

```bash
sudo apt update
sudo apt install -y git openssl curl
```

### Step 3 — Download the GateForge configs

```bash
cd ~
git clone https://github.com/tonylnng/gateforge-openclaw-configs.git
cd gateforge-openclaw-configs/install
```

### Step 4 — Run the Architect setup script

```bash
sudo bash setup-vm1-architect.sh
```

The script will ask you:
1. **Gateway auth token** — Press Enter to auto-generate
2. **Architect hook token** — Press Enter to auto-generate

> Tailscale MagicDNS domains for all 5 VMs (`tonic-architect`, `tonic-designer`, `tonic-developer`, `tonic-qc`, `tonic-operator`, all `.sailfish-bass.ts.net`) are baked into the script — no IPs to type.

All tokens and secrets are auto-generated. Just press Enter for each unless you have specific values.

### Step 5 — Save the output

At the end, the script displays a red box with all the tokens and secrets:

```
┌────────────────────────────────────────────────────────────────┐
│  SAVE THESE VALUES — needed when setting up spoke VMs         │
├────────────────────────────────────────────────────────────────┤
│  Architect Hook Token: e7f3b1a2c9d4...                        │
│  VM-2 Gateway Token:  a3f8c901...    HMAC: 7d2e1a4b...        │
│  VM-3 Gateway Token:  b4c9d012...    HMAC: 8e3f2b5c...        │
│  VM-4 Gateway Token:  c5dae123...    HMAC: 9f4c3d6e...        │
│  VM-5 Gateway Token:  d6ebf234...    HMAC: a05d4e7f...        │
└────────────────────────────────────────────────────────────────┘
```

**Copy these values to a safe place** (e.g., a text file on your Mac). You will paste them into each spoke VM setup.

### Step 6 — (At project start, not now) Clone the project Blueprint repo

The **Blueprint** is a per-project artifact, not part of OpenClaw setup. You only
need it once you start a real project. When that time comes, clone the project's
Blueprint repo to the canonical path `/opt/gateforge/blueprint/`:

```bash
sudo mkdir -p /opt/gateforge
sudo git clone https://github.com/tonylnng/<project>-blueprint.git /opt/gateforge/blueprint
sudo chown -R "$USER:$USER" /opt/gateforge/blueprint
```

Replace `<project>-blueprint` with the actual repo name for the project you are
kicking off (see [GateForge Repositories](#gateforge-repositories) above).

To use a different location, export `BLUEPRINT_REPO=/path/to/blueprint` before
running any Architect tooling.

> The Architect's communication tests (`install/test-communication.sh`) do **not**
> require the Blueprint repo. They push test branches to a separate throwaway
> repo (`tonylnng/gateforge-openclaw-commtest`, baked into `install-common.sh`
> as `COMMTEST_REPO_URL`). The test script clones that repo on demand to
> `/var/tmp/gateforge-commtest/` and deletes the test branches at the end of
> each run. Override with `COMMTEST_REPO_URL=<url>` in `gateforge.env` or
> exported in your shell.

---

## VM-2: System Designer

### Step 1 — Open a terminal on VM-2

```bash
ssh user@tonic-designer
```

### Step 2 — Install prerequisites and download configs

```bash
sudo apt update
sudo apt install -y git openssl curl
cd ~
git clone https://github.com/tonylnng/gateforge-openclaw-configs.git
cd gateforge-openclaw-configs/install
```

### Step 3 — Run the Designer setup script

```bash
sudo bash setup-vm2-designer.sh
```

The script will ask you:
1. **This VM's gateway token** — Paste the **VM-2 Gateway Token** from the VM-1 output
2. **Architect hook token** — Paste the **Architect Hook Token** from the VM-1 output
3. **This VM's HMAC secret** — Paste the **VM-2 HMAC Secret** from the VM-1 output

> Tailscale MagicDNS domains (`tonic-designer.sailfish-bass.ts.net` for this VM, `tonic-architect.sailfish-bass.ts.net` for VM-1) are baked into the script — no IPs to type.

### Step 4 — Done

The script confirms success and shows a summary.

---

## VM-3: Developers

### Step 1 — Open a terminal on VM-3

```bash
ssh user@tonic-developer
```

### Step 2 — Install prerequisites and download configs

```bash
sudo apt update
sudo apt install -y git openssl curl
cd ~
git clone https://github.com/tonylnng/gateforge-openclaw-configs.git
cd gateforge-openclaw-configs/install
```

### Step 3 — Run the Developers setup script

```bash
sudo bash setup-vm3-developers.sh
```

The script asks the same questions as VM-2 (paste VM-3 values from the VM-1 output), plus one extra:

```
How many Developer agents?
  1) 3
  2) 5
  3) 10
Choose [1-3]:
```

Type `1`, `2`, or `3` and press Enter. The script creates per-agent identity files (dev-01, dev-02, etc.).

---

## VM-4: QC Agents

### Step 1 — Open a terminal on VM-4

```bash
ssh user@tonic-qc
```

### Step 2 — Install prerequisites and download configs

```bash
sudo apt update
sudo apt install -y git openssl curl
cd ~
git clone https://github.com/tonylnng/gateforge-openclaw-configs.git
cd gateforge-openclaw-configs/install
```

### Step 3 — Run the QC Agents setup script

```bash
sudo bash setup-vm4-qc-agents.sh
```

Same as VM-3 — paste VM-4 values from VM-1 output, then choose how many QC agents (3, 5, or 10).

---

## VM-5: Operator

### Step 1 — Open a terminal on VM-5

```bash
ssh user@tonic-operator
```

### Step 2 — Install prerequisites and download configs

```bash
sudo apt update
sudo apt install -y git openssl curl
cd ~
git clone https://github.com/tonylnng/gateforge-openclaw-configs.git
cd gateforge-openclaw-configs/install
```

### Step 3 — Run the Operator setup script

```bash
sudo bash setup-vm5-operator.sh
```

Paste VM-5 values from the VM-1 output. Done.

---

## Verify Everything Works

After all 5 VMs are set up, test the notification from any spoke VM.

### On VM-2 (or any spoke), run:

```bash
# Load your config
source <(sudo cat /opt/secrets/gateforge.env)

# Build a test notification
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PAYLOAD='{"name":"agent-notify","agentId":"architect","message":"[INFO] Test from designer","metadata":{"sourceVm":"vm-2","sourceRole":"designer","priority":"INFO","taskId":"TEST","timestamp":"'${TIMESTAMP}'"}}'

# Sign it
SIGNATURE=$(echo -n "${PAYLOAD}" | openssl dgst -sha256 -hmac "${AGENT_SECRET}" | awk '{print $2}')

# Send it
curl -s -X POST ${ARCHITECT_NOTIFY_URL} \
  -H "Authorization: Bearer ${ARCHITECT_HOOK_TOKEN}" \
  -H "X-Agent-Signature: ${SIGNATURE}" \
  -H "X-Source-VM: vm-2" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}"
```

If the Architect is running, you should get a response. If not, you'll see a connection error — that just means the Architect's OpenClaw gateway isn't started yet.

---

## Run Connectivity Tests

After all VMs are set up, run the test scripts to verify everything works.

### Test from VM-1 (Architect) — tests ALL VMs

```bash
cd ~/gateforge-openclaw-configs
sudo bash install/test-connectivity.sh
```

This runs 6 tests from the Architect: ping all spokes, gateway health check on all 5 VMs, task dispatch to each spoke, HMAC notification from each spoke, fake-secret rejection, and config file presence. Only works on VM-1 because the Architect has all spoke tokens.

### Test from any spoke VM (VM-2 through VM-5)

```bash
cd ~/gateforge-openclaw-configs
sudo bash install/test-spoke.sh
```

This runs 5 tests from the spoke: ping Architect, Architect gateway health, local gateway health, HMAC notification to Architect, and wrong-token rejection. Works on any spoke VM — it reads the role and credentials from `/opt/secrets/gateforge.env`.

### Expected Results

All tests should show green `PASS`. Common issues:

| Issue | Cause | Fix |
|-------|-------|-----|
| Ping fails | Tailscale not connected | `tailscale status` on both VMs |
| Gateway HTTP fails | Bound to loopback | `openclaw config set gateway.bind tailnet` + restart |
| Connection refused | Firewall blocking | `sudo ufw allow from <vm-ip> to any port 18789` |
| HTTP 404 on dispatch | Hook endpoint not configured | See next section for OpenClaw webhook setup |

---

## GitHub Token Storage

After all 5 VMs have been set up and connectivity tests pass, configure GitHub tokens so the OpenClaw gateway process can access repositories at runtime.

**Method:** Dedicated secrets file sourced from the shell profile — tokens are loaded into the user session environment, so the OpenClaw process (started via `openclaw gateway restart`) inherits them automatically. The file is stored outside the workspace with `600` permissions.

> **Prerequisites:** OpenClaw installed and gateway working, GitHub Fine-Grained PATs already generated per the [GitHub Token Configuration](../README.md#github-token-configuration) section in the README.

### Token Plan

| Variable | Purpose | Scope | Repos |
|----------|---------|-------|-------|
| `GITHUB_TOKEN_READONLY` | Read-only access (Token A) | `contents:read` | All GateForge repos |
| `GITHUB_TOKEN_RW` | Read/write for Blueprint or Code (Token B/C/D) | `contents:write` | VM-specific target repo only |

- **All VMs** need `GITHUB_TOKEN_READONLY` (Token A)
- **VM-1** also needs `GITHUB_TOKEN_RW` for the project Blueprint repo (Token B)
- **VM-3** also needs `GITHUB_TOKEN_RW` for the project code repo (Token C)
- **VM-5** also needs `GITHUB_TOKEN_RW` for the project code repo (Token D)
- **VM-2 and VM-4** only need `GITHUB_TOKEN_READONLY`

### Step 1: Create the secrets file

Run this as the OpenClaw user (not root).

**For VM-1 (Architect), VM-3 (Developers), VM-5 (Operator)** — two tokens:

```bash
mkdir -p ~/.config/gateforge
cat > ~/.config/gateforge/github-tokens.env << 'EOF'
# GateForge GitHub tokens — DO NOT COMMIT TO GIT
export GITHUB_TOKEN_READONLY="<paste-token-a-here>"
export GITHUB_TOKEN_RW="<paste-token-b-here>"
EOF
```

**For VM-2 (Designer), VM-4 (QC Agents)** — read-only token only:

```bash
mkdir -p ~/.config/gateforge
cat > ~/.config/gateforge/github-tokens.env << 'EOF'
# GateForge GitHub tokens — DO NOT COMMIT TO GIT
export GITHUB_TOKEN_READONLY="<paste-token-a-here>"
EOF
```

Replace `<paste-token-a-here>` and `<paste-token-b-here>` with actual token values.

### Step 2: Lock down permissions

```bash
chmod 600 ~/.config/gateforge/github-tokens.env
```

### Step 3: Auto-load tokens in the shell session

Add to `~/.bashrc` so tokens are available whenever you log in or the gateway starts:

```bash
echo '' >> ~/.bashrc
echo '# GateForge GitHub tokens' >> ~/.bashrc
echo '[ -f ~/.config/gateforge/github-tokens.env ] && source ~/.config/gateforge/github-tokens.env' >> ~/.bashrc
```

Load them into the current session immediately:

```bash
source ~/.config/gateforge/github-tokens.env
```

### Step 4: Restart the gateway

The gateway inherits environment variables from the user session:

```bash
openclaw gateway restart
```

### Step 5: Verify

**5a. Gateway is running:**

```bash
openclaw gateway status
# Expected: Runtime: running
```

**5b. Environment variables are set:**

```bash
env | grep GITHUB_TOKEN
# Expected: GITHUB_TOKEN_READONLY=ghp_xxx... (and GITHUB_TOKEN_RW on VM-1/3/5)
```

**5c. Read-only token works:**

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN_READONLY" \
  https://api.github.com/repos/tonylnng/gateforge-openclaw-configs
# Expected: 200
```

**5d. Read/write token works (VM-1, VM-3, VM-5 only):**

```bash
# Just verify auth — no writes
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN_RW" \
  https://api.github.com/repos/tonylnng/<project>-blueprint
# Expected: 200
```

**5e. Telegram channel still works:**

Send a message to the Telegram bot and confirm it responds.

### Step 6: Configure git credential helper (recommended)

So `git clone`/`pull`/`push` uses the token natively without it appearing in command args:

```bash
# Default: read-only access for all repos (all VMs)
git config --global credential.https://github.com.helper \
  '!f() { echo "username=x-access-token"; echo "password=$GITHUB_TOKEN_READONLY"; }; f'
```

For repos that need write access (VM-1, VM-3, VM-5), override per-repo:

```bash
cd /path/to/<project>-blueprint   # or <project>-code
git config credential.https://github.com.helper \
  '!f() { echo "username=x-access-token"; echo "password=$GITHUB_TOKEN_RW"; }; f'
```

### Security Notes

| Rule | Detail |
|------|--------|
| Never commit `github-tokens.env` to git | It contains raw tokens |
| Never put tokens in `openclaw.json`, `USER.md`, `TOOLS.md`, or any workspace file | The agent can read workspace files — tokens would be exposed |
| Rotate every 90 days | Set expiry in GitHub when generating the PAT |
| Use fine-grained PATs with minimum scope | See the README for exact permissions per token type |
| Agent CAN read env vars at runtime | This is by design — it needs them for git/API access |
| This protects against accidental file exposure | Not against the agent process itself |

### Rollback

To remove tokens from a VM:

```bash
rm ~/.config/gateforge/github-tokens.env
# Remove the source line from ~/.bashrc
sed -i '/gateforge\/github-tokens.env/d' ~/.bashrc
sed -i '/GateForge GitHub tokens/d' ~/.bashrc
# Unset from current session
unset GITHUB_TOKEN_READONLY GITHUB_TOKEN_RW
# Restart gateway without tokens
openclaw gateway restart
```

### File Locations

| File | Purpose |
|------|---------|
| `~/.config/gateforge/github-tokens.env` | Token storage (this setup) |
| `~/.bashrc` | Sources the token file on login |

---

## Quick Reference — Common Commands

| What | Command |
|------|---------|
| Check OpenClaw is running | `openclaw gateway status` |
| View your GateForge config | `sudo cat /opt/secrets/gateforge.env` |
| Re-run setup (update config) | `cd ~/gateforge-openclaw-configs/install && sudo bash setup-vmN-role.sh` |
| Update configs from GitHub | `cd ~/gateforge-openclaw-configs && git pull` |
| Restart OpenClaw gateway | `openclaw gateway restart` |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `openssl: command not found` | `sudo apt install -y openssl` |
| `git: command not found` | `sudo apt install -y git` |
| `Permission denied` on gateforge.env | Run the setup script with `sudo`. If the OpenClaw user still can't read it: `sudo setfacl -m u:<user>:r /opt/secrets/gateforge.env` |
| `setfacl: command not found` | Install the ACL package: `sudo apt-get install acl` |
| Script says "OpenClaw not found" | Install OpenClaw first: `curl -fsSL https://openclaw.ai/install.sh \| bash` |
| "Connection refused" on test notification | The Architect's OpenClaw gateway isn't running — start it first |
| "origin not allowed" on Control UI | The setup scripts auto-configure this. To fix manually: `openclaw config set gateway.controlUi.allowedOrigins '["http://<VM_TAILSCALE_IP>:18789"]'` then `openclaw gateway restart` |
| Wrong values pasted | Re-run the setup script — it will overwrite the old config |

---

*GateForge — Multi-Agent SDLC Pipeline | Designed by Tony NG | April 2026*
