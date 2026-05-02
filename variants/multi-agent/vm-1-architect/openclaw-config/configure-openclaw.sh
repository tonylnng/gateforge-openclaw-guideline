#!/usr/bin/env bash
# =============================================================================
# GateForge — VM-1: System Architect (Hub)
# Configure OpenClaw for hub-and-spoke inter-agent communication
# =============================================================================
# This script PATCHES the existing openclaw.json — it does NOT overwrite it.
# Any settings already configured (models, auth profiles, channels) are preserved.
#
# Prerequisites:
#   - OpenClaw installed and working (wizard already run)
#   - /opt/secrets/gateforge.env exists (from setup-vm1-architect.sh)
#
# Usage:
#   sudo bash configure-openclaw.sh [--dry-run]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve the OpenClaw user (not root when running under sudo)
# ---------------------------------------------------------------------------
OC_USER="${SUDO_USER:-$(whoami)}"
OC_HOME=$(eval echo "~${OC_USER}")
OC_CONFIG="${OC_HOME}/.openclaw/openclaw.json"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
TEAL='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true && echo -e "${YELLOW}DRY RUN — no changes will be made${RESET}"

# ---------------------------------------------------------------------------
# Load GateForge tokens
# ---------------------------------------------------------------------------
CONFIG_FILE="/opt/secrets/gateforge.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo -e "${RED}✗ /opt/secrets/gateforge.env not found${RESET}"
  echo -e "  Run setup-vm1-architect.sh first to generate tokens."
  exit 1
fi
set -a; source "$CONFIG_FILE"; set +a
echo -e "${GREEN}✓${RESET} Loaded tokens from ${CONFIG_FILE}"

# ---------------------------------------------------------------------------
# Validate required variables
# ---------------------------------------------------------------------------
for var in GATEWAY_AUTH_TOKEN ARCHITECT_HOOK_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    echo -e "${RED}✗ Required variable ${var} is not set in ${CONFIG_FILE}${RESET}"
    exit 1
  fi
done
echo -e "${GREEN}✓${RESET} All required tokens present"

# ---------------------------------------------------------------------------
# Helper: run openclaw config set (as the OC user, not root)
# ---------------------------------------------------------------------------
oc_set() {
  local key="$1"
  local value="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${DIM}[dry-run] openclaw config set ${key} ${value}${RESET}"
  else
    sudo -u "$OC_USER" openclaw config set "$key" "$value" 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# Helper: patch config with JSON5 merge (preserves all existing settings)
# ---------------------------------------------------------------------------
oc_patch() {
  local description="$1"
  local json5_payload="$2"

  echo -e "${TEAL}→${RESET} ${description}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${DIM}[dry-run] Would patch:${RESET}"
    echo "$json5_payload" | sed 's/^/    /'
    return
  fi

  # Get current config hash for optimistic concurrency
  local hash
  hash=$(sudo -u "$OC_USER" openclaw gateway call config.get --params '{}' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('payload',{}).get('hash',''))" 2>/dev/null || echo "")

  if [[ -n "$hash" ]]; then
    # Gateway is running — use live patch
    sudo -u "$OC_USER" openclaw gateway call config.patch --params "$(python3 -c "
import json
print(json.dumps({
    'raw': '''${json5_payload}''',
    'baseHash': '${hash}',
    'note': 'GateForge hub config'
}))
")" 2>/dev/null && echo -e "  ${GREEN}✓${RESET} Patched (live)" || {
      echo -e "  ${YELLOW}!${RESET} Live patch failed — falling back to file edit"
      patch_file "$json5_payload"
    }
  else
    # Gateway not running — patch the file directly
    patch_file "$json5_payload"
  fi
}

# ---------------------------------------------------------------------------
# File-based JSON5 patch (when Gateway is not running)
# ---------------------------------------------------------------------------
patch_file() {
  local json5_payload="$1"

  python3 -c "
import json, sys, os, copy

config_path = '${OC_CONFIG}'

# Read existing config
try:
    # JSON5 may have comments — strip them for json.loads
    with open(config_path) as f:
        raw = f.read()
    # Simple comment stripping (single-line // comments)
    import re
    stripped = re.sub(r'//[^\n]*', '', raw)
    stripped = re.sub(r',\s*([}\]])', r'\1', stripped)  # trailing commas
    # Unquoted keys → quoted keys (basic JSON5 → JSON)
    stripped = re.sub(r'(?<=[{,\n])\s*([a-zA-Z_]\w*)\s*:', r' \"\1\":', stripped)
    cfg = json.loads(stripped)
except Exception as e:
    print(f'Warning: could not parse existing config ({e}), creating minimal', file=sys.stderr)
    cfg = {}

# Parse the patch payload (same JSON5 handling)
patch_raw = '''${json5_payload}'''
patch_stripped = re.sub(r'//[^\n]*', '', patch_raw)
patch_stripped = re.sub(r',\s*([}\]])', r'\1', patch_stripped)
patch_stripped = re.sub(r'(?<=[{,\n])\s*([a-zA-Z_]\w*)\s*:', r' \"\1\":', patch_stripped)
patch = json.loads(patch_stripped)

# Deep merge
def deep_merge(base, override):
    result = copy.deepcopy(base)
    for k, v in override.items():
        if v is None:
            result.pop(k, None)
        elif isinstance(v, dict) and isinstance(result.get(k), dict):
            result[k] = deep_merge(result[k], v)
        else:
            result[k] = copy.deepcopy(v)
    return result

merged = deep_merge(cfg, patch)

# Write back
with open(config_path, 'w') as f:
    json.dump(merged, f, indent=2)

# Fix ownership
os.system(f'chown ${OC_USER}:${OC_USER} {config_path}')
print('  OK — file patched')
" 2>&1 && echo -e "  ${GREEN}✓${RESET} Config file updated" || echo -e "  ${RED}✗${RESET} File patch failed"
}

# =============================================================================
# Apply GateForge configuration (patches into existing config)
# =============================================================================
echo ""
echo -e "${TEAL}${BOLD}Configuring OpenClaw for VM-1: System Architect (Hub)${RESET}"
echo -e "${TEAL}$(printf '─%.0s' {1..55})${RESET}"
echo -e "${DIM}This patches GateForge settings into your existing config.${RESET}"
echo -e "${DIM}Existing settings (models, auth, channels) are preserved.${RESET}"
echo ""

# --- 1. Gateway: bind to tailnet with token auth ---
echo -e "${BOLD}[1/5] Gateway${RESET}"
oc_set "gateway.bind" "tailnet"
oc_set "gateway.auth.mode" "token"
oc_set "gateway.auth.token" "$GATEWAY_AUTH_TOKEN"
oc_set "gateway.auth.allowTailscale" "false"
echo -e "  ${GREEN}✓${RESET} Gateway: tailnet bind + token auth"

# --- 2. Hooks: enable webhook endpoint for spoke notifications ---
echo ""
echo -e "${BOLD}[2/5] Hooks (webhook endpoint)${RESET}"
oc_patch "Enable hooks for inter-VM communication" '{
  hooks: {
    enabled: true,
    token: "'"${ARCHITECT_HOOK_TOKEN}"'",
    path: "/hooks",
    defaultSessionKey: "hook:gateforge",
    allowRequestSessionKey: true,
    allowedSessionKeyPrefixes: ["hook:", "gateforge:"],
    mappings: [
      {
        match: { path: "agent" },
        action: "agent",
        agentId: "architect",
        deliver: true
      }
    ]
  }
}'

# --- 3. Agent: ensure "architect" agent exists with correct workspace ---
echo ""
echo -e "${BOLD}[3/5] Agent identity${RESET}"
# Check if architect agent already exists
if sudo -u "$OC_USER" openclaw agents list 2>/dev/null | grep -q "architect"; then
  echo -e "  ${GREEN}✓${RESET} Agent 'architect' already exists"
else
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${DIM}[dry-run] openclaw agents add --id architect --workspace ~/.openclaw/workspace --non-interactive${RESET}"
  else
    sudo -u "$OC_USER" openclaw agents add --id "architect" --workspace "${OC_HOME}/.openclaw/workspace" --non-interactive 2>/dev/null || \
      echo -e "  ${YELLOW}!${RESET} Could not add agent via CLI — may need manual setup"
  fi
fi
oc_set "agents.defaults.model.primary" "anthropic/claude-opus-4-6"
oc_set "agents.defaults.model.fallbacks" '["anthropic/claude-sonnet-4-6"]'
oc_set "agents.defaults.heartbeat.every" "30m"
echo -e "  ${GREEN}✓${RESET} Agent defaults set (Opus 4.6 primary)"

# --- 4. Sessions ---
echo ""
echo -e "${BOLD}[4/5] Sessions & Cron${RESET}"
oc_set "session.dmScope" "per-channel-peer"
oc_set "session.reset.mode" "idle"
oc_set "session.reset.idleMinutes" "240"
oc_set "cron.enabled" "true"
oc_set "cron.maxConcurrentRuns" "2"
echo -e "  ${GREEN}✓${RESET} Sessions: per-channel-peer, 4hr idle reset"
echo -e "  ${GREEN}✓${RESET} Cron: enabled (max 2 concurrent)"

# --- 5. Logging ---
echo ""
echo -e "${BOLD}[5/5] Logging${RESET}"
oc_set "logging.level" "info"
oc_set "logging.consoleLevel" "warn"
echo -e "  ${GREEN}✓${RESET} Logging: info (file) / warn (console)"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${TEAL}$(printf '─%.0s' {1..55})${RESET}"
echo -e "${GREEN}${BOLD}VM-1 Architect — OpenClaw configuration complete${RESET}"
echo ""
echo -e "  ${BOLD}What was configured:${RESET}"
echo -e "    • Gateway bound to Tailscale interface with token auth"
echo -e "    • Webhook hooks enabled (spokes POST to /hooks/agent)"
echo -e "    • Architect agent with Opus 4.6 model"
echo -e "    • Cron enabled for scheduled tasks"
echo ""
echo -e "  ${BOLD}What was NOT touched:${RESET}"
echo -e "    • Existing channels (Telegram, etc.)"
echo -e "    • Existing auth profiles and API keys"
echo -e "    • Existing tools and skills configuration"
echo -e "    • Any other agents you may have configured"
echo ""
if [[ "$DRY_RUN" == "false" ]]; then
  echo -e "  ${YELLOW}→ Restart required:${RESET} openclaw gateway restart"
  echo -e "    (gateway.* changes require a restart to take effect)"
fi
echo ""
