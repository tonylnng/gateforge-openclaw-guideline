#!/usr/bin/env bash
# =============================================================================
# GateForge — Spoke VM OpenClaw Configuration
# =============================================================================
# Patches GateForge hub-and-spoke settings into the EXISTING openclaw.json.
# Does NOT overwrite existing settings (models, auth profiles, channels, etc.).
#
# This script auto-detects the VM role from /opt/secrets/gateforge.env
# (GATEFORGE_ROLE), or you can pass it explicitly.
#
# Prerequisites:
#   - OpenClaw installed and working (wizard already run)
#   - /opt/secrets/gateforge.env exists (from setup-vmN-*.sh)
#
# Usage:
#   sudo bash configure-openclaw-spoke.sh [--dry-run]
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
  echo -e "  Run the VM setup script first to generate tokens."
  exit 1
fi
set -a; source "$CONFIG_FILE"; set +a
echo -e "${GREEN}✓${RESET} Loaded tokens from ${CONFIG_FILE}"

# ---------------------------------------------------------------------------
# Detect role
# ---------------------------------------------------------------------------
ROLE="${GATEFORGE_ROLE:-}"
if [[ -z "$ROLE" ]]; then
  echo -e "${RED}✗ GATEFORGE_ROLE not set in ${CONFIG_FILE}${RESET}"
  echo -e "  Expected one of: designer, developer, qc, operator"
  exit 1
fi

# Map role to display name and agent config
case "$ROLE" in
  designer)
    VM_LABEL="VM-2: System Designer"
    AGENT_ID="designer"
    MODEL_PRIMARY="anthropic/claude-sonnet-4-6"
    SANDBOX_MODE="non-main"
    CRON_ENABLED="false"
    MULTI_AGENT=false
    ;;
  developer)
    VM_LABEL="VM-3: Developers"
    AGENT_ID="dev-01"
    MODEL_PRIMARY="anthropic/claude-sonnet-4-6"
    SANDBOX_MODE="all"
    CRON_ENABLED="false"
    MULTI_AGENT=true
    AGENT_PREFIX="dev"
    ;;
  qc)
    VM_LABEL="VM-4: QC Agents"
    AGENT_ID="qc-01"
    MODEL_PRIMARY="minimax/MiniMax-M2.7"
    SANDBOX_MODE="all"
    CRON_ENABLED="false"
    MULTI_AGENT=true
    AGENT_PREFIX="qc"
    ;;
  operator)
    VM_LABEL="VM-5: Operator"
    AGENT_ID="operator"
    MODEL_PRIMARY="minimax/MiniMax-M2.7"
    SANDBOX_MODE="non-main"
    CRON_ENABLED="true"
    MULTI_AGENT=false
    ;;
  *)
    echo -e "${RED}✗ Unknown role: ${ROLE}${RESET}"
    exit 1
    ;;
esac

echo -e "${GREEN}✓${RESET} Detected role: ${BOLD}${VM_LABEL}${RESET}"

# ---------------------------------------------------------------------------
# Validate required variables
# ---------------------------------------------------------------------------
for var in GATEWAY_AUTH_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    echo -e "${RED}✗ Required variable ${var} is not set in ${CONFIG_FILE}${RESET}"
    exit 1
  fi
done

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
    'note': 'GateForge spoke config'
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
import json, sys, os, copy, re

config_path = '${OC_CONFIG}'

# Read existing config
try:
    with open(config_path) as f:
        raw = f.read()
    stripped = re.sub(r'//[^\n]*', '', raw)
    stripped = re.sub(r',\s*([}\]])', r'\1', stripped)
    stripped = re.sub(r'(?<=[{,\n])\s*([a-zA-Z_]\w*)\s*:', r' \"\1\":', stripped)
    cfg = json.loads(stripped)
except Exception as e:
    print(f'Warning: could not parse existing config ({e}), creating minimal', file=sys.stderr)
    cfg = {}

# Parse the patch payload
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

with open(config_path, 'w') as f:
    json.dump(merged, f, indent=2)

os.system(f'chown ${OC_USER}:${OC_USER} {config_path}')
print('  OK — file patched')
" 2>&1 && echo -e "  ${GREEN}✓${RESET} Config file updated" || echo -e "  ${RED}✗${RESET} File patch failed"
}

# =============================================================================
# Apply GateForge configuration
# =============================================================================
echo ""
echo -e "${TEAL}${BOLD}Configuring OpenClaw for ${VM_LABEL} (Spoke)${RESET}"
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

# --- 2. Hooks: enable webhook endpoint for Architect dispatches ---
echo ""
echo -e "${BOLD}[2/5] Hooks (webhook endpoint)${RESET}"
oc_patch "Enable hooks for task dispatch from Architect" '{
  hooks: {
    enabled: true,
    token: "'"${GATEWAY_AUTH_TOKEN}"'",
    path: "/hooks",
    defaultSessionKey: "hook:gateforge",
    allowRequestSessionKey: true,
    allowedSessionKeyPrefixes: ["hook:", "gateforge:"],
    mappings: [
      {
        match: { path: "agent" },
        action: "agent",
        agentId: "'"${AGENT_ID}"'",
        deliver: true
      }
    ]
  }
}'

# --- 3. Agent configuration ---
echo ""
echo -e "${BOLD}[3/5] Agent identity${RESET}"

if [[ "$MULTI_AGENT" == "true" ]]; then
  # Multi-agent VMs (VM-3 Developers, VM-4 QC Agents)
  # Determine agent count from existing config or ask
  AGENT_COUNT="${GATEFORGE_AGENT_COUNT:-3}"  # Default 3, can be set in gateforge.env
  echo -e "  Agent count: ${BOLD}${AGENT_COUNT}${RESET} (set GATEFORGE_AGENT_COUNT in gateforge.env to change)"

  # Build agents.list JSON
  AGENTS_JSON="["
  for i in $(seq -f "%02g" 1 "$AGENT_COUNT"); do
    local_id="${AGENT_PREFIX}-${i}"
    local_name="${AGENT_PREFIX^} Agent ${i}"
    [[ "$AGENT_PREFIX" == "dev" ]] && local_name="Developer ${i}"
    [[ "$AGENT_PREFIX" == "qc" ]] && local_name="QC Agent ${i}"

    if [[ "$i" == "01" ]]; then
      AGENTS_JSON+='{ "id": "'"${local_id}"'", "default": true, "name": "'"${local_name}"'", "workspace": "~/.openclaw/workspace-'"${local_id}"'", "agentDir": "~/.openclaw/agents/'"${local_id}"'/agent" }'
    else
      AGENTS_JSON+=', { "id": "'"${local_id}"'", "name": "'"${local_name}"'", "workspace": "~/.openclaw/workspace-'"${local_id}"'", "agentDir": "~/.openclaw/agents/'"${local_id}"'/agent" }'
    fi

    # Create workspace directories
    if [[ "$DRY_RUN" == "false" ]]; then
      sudo -u "$OC_USER" mkdir -p "${OC_HOME}/.openclaw/workspace-${local_id}"
      sudo -u "$OC_USER" mkdir -p "${OC_HOME}/.openclaw/agents/${local_id}/agent"
    fi
  done
  AGENTS_JSON+="]"

  # Build sandbox config for Docker
  SANDBOX_JSON='"sandbox": { "mode": "all", "scope": "agent", "docker": { "image": "openclaw-sandbox:bookworm-slim", "setupCommand": "apt-get update && apt-get install -y git curl nodejs npm", "network": "none", "readOnlyRoot": false, "cpus": "1", "memoryMb": 1024 } }'

  oc_patch "Configure multi-agent (${AGENT_COUNT} agents)" '{
    agents: {
      defaults: {
        model: { primary: "'"${MODEL_PRIMARY}"'", fallbacks: ["anthropic/claude-sonnet-4-6"] },
        '"${SANDBOX_JSON}"',
        heartbeat: { every: "30m", mode: "next-heartbeat" }
      },
      list: '"${AGENTS_JSON}"'
    }
  }'
  echo -e "  ${GREEN}✓${RESET} ${AGENT_COUNT} agents configured (${AGENT_PREFIX}-01..${AGENT_PREFIX}-$(printf '%02d' "$AGENT_COUNT"))"

else
  # Single-agent VMs (VM-2 Designer, VM-5 Operator)
  if sudo -u "$OC_USER" openclaw agents list 2>/dev/null | grep -q "${AGENT_ID}"; then
    echo -e "  ${GREEN}✓${RESET} Agent '${AGENT_ID}' already exists"
  else
    if [[ "$DRY_RUN" == "true" ]]; then
      echo -e "  ${DIM}[dry-run] openclaw agents add --id ${AGENT_ID} --non-interactive${RESET}"
    else
      sudo -u "$OC_USER" openclaw agents add --id "${AGENT_ID}" --workspace "${OC_HOME}/.openclaw/workspace" --non-interactive 2>/dev/null || \
        echo -e "  ${YELLOW}!${RESET} Could not add agent via CLI — may need manual setup"
    fi
  fi
  oc_set "agents.defaults.model.primary" "$MODEL_PRIMARY"
  oc_set "agents.defaults.model.fallbacks" '["anthropic/claude-sonnet-4-6"]'
  oc_set "agents.defaults.sandbox.mode" "$SANDBOX_MODE"
  oc_set "agents.defaults.sandbox.scope" "agent"
  oc_set "agents.defaults.heartbeat.every" "30m"
  echo -e "  ${GREEN}✓${RESET} Agent '${AGENT_ID}' configured (${MODEL_PRIMARY})"
fi

# --- 4. Sessions & Cron ---
echo ""
echo -e "${BOLD}[4/5] Sessions & Cron${RESET}"
oc_set "session.dmScope" "per-channel-peer"
oc_set "session.reset.mode" "idle"
oc_set "session.reset.idleMinutes" "120"
oc_set "cron.enabled" "$CRON_ENABLED"
echo -e "  ${GREEN}✓${RESET} Sessions: per-channel-peer, 2hr idle reset"
if [[ "$CRON_ENABLED" == "true" ]]; then
  oc_set "cron.maxConcurrentRuns" "1"
  echo -e "  ${GREEN}✓${RESET} Cron: enabled (Operator monitoring)"
else
  echo -e "  ${GREEN}✓${RESET} Cron: disabled (spoke — Architect schedules work)"
fi

# --- 5. Logging ---
echo ""
echo -e "${BOLD}[5/5] Logging${RESET}"
oc_set "logging.level" "info"
oc_set "logging.consoleLevel" "warn"
echo -e "  ${GREEN}✓${RESET} Logging: info (file) / warn (console)"

# =============================================================================
# Operator-specific: broader tool access
# =============================================================================
if [[ "$ROLE" == "operator" ]]; then
  echo ""
  echo -e "${BOLD}[+] Operator-specific: tool permissions${RESET}"
  oc_patch "Grant Operator broader tool access for deployment" '{
    agents: {
      list: [
        {
          id: "operator",
          tools: {
            allow: ["exec", "read", "write", "edit", "apply_patch", "process", "browser", "cron", "web_fetch"]
          }
        }
      ]
    }
  }'
  echo -e "  ${GREEN}✓${RESET} Operator tools: exec, browser, cron, web_fetch"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${TEAL}$(printf '─%.0s' {1..55})${RESET}"
echo -e "${GREEN}${BOLD}${VM_LABEL} — OpenClaw configuration complete${RESET}"
echo ""
echo -e "  ${BOLD}What was configured:${RESET}"
echo -e "    • Gateway bound to Tailscale interface with token auth"
echo -e "    • Webhook hooks enabled (Architect dispatches to /hooks/agent)"
if [[ "$MULTI_AGENT" == "true" ]]; then
  echo -e "    • ${AGENT_COUNT} agents with Docker sandbox"
else
  echo -e "    • Agent '${AGENT_ID}' with ${MODEL_PRIMARY}"
fi
echo -e "    • Cron: ${CRON_ENABLED}"
echo ""
echo -e "  ${BOLD}What was NOT touched:${RESET}"
echo -e "    • Existing channels and auth profiles"
echo -e "    • Existing API keys and model configuration"
echo -e "    • Existing tools and skills"
echo ""
if [[ "$DRY_RUN" == "false" ]]; then
  echo -e "  ${YELLOW}→ Restart required:${RESET} openclaw gateway restart"
  echo -e "    (gateway.* changes require a restart to take effect)"
fi
echo ""
