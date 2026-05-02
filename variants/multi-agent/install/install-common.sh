#!/usr/bin/env bash
# =============================================================================
# GateForge — Shared Setup Functions
# =============================================================================
# Sourced by all VM-specific setup scripts.
# Do NOT run this file directly.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Version & Constants
# ---------------------------------------------------------------------------
GATEFORGE_VERSION="2.0.0"
OPENCLAW_PORT=18789
CONFIG_FILE="/opt/secrets/gateforge.env"
# Throwaway target repo for end-to-end communication tests. Spoke agents push
# TASK-COMMTEST-* branches here; install/test-communication.sh deletes them
# after each run. Not used by any project — comm test only.
COMMTEST_REPO_URL="https://github.com/tonylnng/gateforge-openclaw-commtest.git"
OPENCLAW_CONFIG_DIR="$HOME/.openclaw"
OPENCLAW_WORKSPACE_DIR="$HOME/.openclaw/workspace"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
TEAL='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
DRY_RUN="${DRY_RUN:-false}"
TOTAL_STEPS="${TOTAL_STEPS:-6}"
CURRENT_STEP=0

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
print_banner() {
  echo ""
  echo -e "${TEAL}${BOLD}"
  cat << 'BANNER'
   ██████╗  █████╗ ████████╗███████╗███████╗ ██████╗ ██████╗  ██████╗ ███████╗
  ██╔════╝ ██╔══██╗╚══██╔══╝██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝
  ██║  ███╗███████║   ██║   █████╗  █████╗  ██║   ██║██████╔╝██║  ███╗█████╗
  ██║   ██║██╔══██║   ██║   ██╔══╝  ██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝
  ╚██████╔╝██║  ██║   ██║   ███████╗██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
   ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
BANNER
  echo -e "${RESET}"
  echo -e "  ${DIM}Multi-Agent SDLC Pipeline — Communication Setup v${GATEFORGE_VERSION}${RESET}"
  echo -e "  ${DIM}Assumes OpenClaw is already installed with API keys configured.${RESET}"
  echo ""
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
print_step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  echo ""
  echo -e "${TEAL}${BOLD}[${CURRENT_STEP}/${TOTAL_STEPS}] $1${RESET}"
  echo -e "${TEAL}$(printf '%.0s─' {1..60})${RESET}"
}

print_success() { echo -e "  ${GREEN}✓${RESET} $1"; }
print_error()   { echo -e "  ${RED}✗${RESET} $1"; }
print_warn()    { echo -e "  ${YELLOW}!${RESET} $1"; }
print_info()    { echo -e "  ${BLUE}→${RESET} $1"; }

# ---------------------------------------------------------------------------
# Input helpers
# ---------------------------------------------------------------------------
prompt_required() {
  local var_name="$1"
  local prompt_text="$2"
  local default="${3:-}"
  local value=""

  while [[ -z "$value" ]]; do
    if [[ -n "$default" ]]; then
      echo -en "  ${BOLD}${prompt_text}${RESET} [${DIM}${default}${RESET}]: "
      read -r value
      value="${value:-$default}"
    else
      echo -en "  ${BOLD}${prompt_text}${RESET}: "
      read -r value
    fi
    if [[ -z "$value" ]]; then
      print_error "This field is required."
    fi
  done

  eval "$var_name='$value'"
}

prompt_secret() {
  local var_name="$1"
  local prompt_text="$2"
  local default="${3:-}"
  local value=""

  while [[ -z "$value" ]]; do
    if [[ -n "$default" ]]; then
      echo -en "  ${BOLD}${prompt_text}${RESET} [${DIM}press Enter to auto-generate${RESET}]: "
    else
      echo -en "  ${BOLD}${prompt_text}${RESET}: "
    fi
    read -rs value
    echo ""
    if [[ -z "$value" && -n "$default" ]]; then
      value="$default"
      print_info "Auto-generated: ${value:0:8}...${value: -4}"
    elif [[ -z "$value" ]]; then
      print_error "This field is required."
    fi
  done

  eval "$var_name='$value'"
}

prompt_choice() {
  local var_name="$1"
  local prompt_text="$2"
  shift 2
  local options=("$@")
  local value=""

  echo -e "  ${BOLD}${prompt_text}${RESET}"
  for i in "${!options[@]}"; do
    echo -e "    ${TEAL}$((i+1)))${RESET} ${options[$i]}"
  done

  while [[ -z "$value" ]]; do
    echo -en "  ${BOLD}Choose [1-${#options[@]}]${RESET}: "
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      value="${options[$((choice-1))]}"
    else
      print_error "Invalid choice."
    fi
  done

  eval "$var_name='$value'"
}

confirm_continue() {
  echo ""
  echo -en "  ${BOLD}$1${RESET} [Y/n]: "
  read -r answer
  if [[ "${answer,,}" == "n" ]]; then
    echo -e "  ${YELLOW}Aborted.${RESET}"
    exit 0
  fi
}

# ---------------------------------------------------------------------------
# Secret generation
# ---------------------------------------------------------------------------
generate_secret() {
  openssl rand -hex 32
}

# ---------------------------------------------------------------------------
# Config file management
# ---------------------------------------------------------------------------
write_config() {
  local config_content="$1"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_warn "[DRY RUN] Would write to ${CONFIG_FILE}:"
    echo "$config_content" | sed 's/^/    /'
    return
  fi

  sudo mkdir -p "$(dirname "$CONFIG_FILE")"
  echo "$config_content" | sudo tee "$CONFIG_FILE" > /dev/null
  sudo chown root:root "$CONFIG_FILE"
  sudo chmod 600 "$CONFIG_FILE"
  print_success "Config written to ${CONFIG_FILE} (root:root, 600)"

  # Grant read access to the OpenClaw user via ACL
  # The file is root:root 600 so the non-root OpenClaw user can't read it otherwise
  local oc_user="${SUDO_USER:-$(whoami)}"
  if [[ "$oc_user" != "root" ]] && command -v setfacl &>/dev/null; then
    sudo setfacl -m "u:${oc_user}:r" "$CONFIG_FILE"
    print_success "ACL read access granted to user '${oc_user}'"
  elif [[ "$oc_user" != "root" ]]; then
    print_warn "setfacl not found — install acl package: sudo apt-get install acl"
    print_warn "Then run: sudo setfacl -m u:${oc_user}:r ${CONFIG_FILE}"
  fi
}

load_existing_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    print_info "Found existing config at ${CONFIG_FILE}"
    # Source it to pre-fill values (sudo needed)
    eval "$(sudo cat "$CONFIG_FILE" 2>/dev/null | grep -v '^#' | grep '=')" 2>/dev/null || true
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Copy config MD files
# ---------------------------------------------------------------------------
copy_config_files() {
  local vm_dir="$1"
  local oc_user="${SUDO_USER:-$(whoami)}"
  local oc_home
  oc_home=$(eval echo "~${oc_user}")
  local workspace="${oc_home}/.openclaw/workspace"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_warn "[DRY RUN] Would copy files from ${vm_dir} to ${workspace}"
    return
  fi

  # Ensure workspace directory exists with correct ownership
  sudo -u "$oc_user" mkdir -p "$workspace"

  # Copy agent identity files to workspace (where OpenClaw reads them)
  for f in SOUL.md AGENTS.md USER.md TOOLS.md; do
    if [[ -f "${vm_dir}/${f}" ]]; then
      sudo cp "${vm_dir}/${f}" "${workspace}/${f}"
      sudo chown "${oc_user}:${oc_user}" "${workspace}/${f}"
      print_success "Copied ${f} → ${workspace}/${f}"
    fi
  done

  # Copy guideline docs to workspace
  for f in BLUEPRINT-GUIDE.md RESILIENCE-SECURITY-GUIDE.md DEVELOPMENT-GUIDE.md QA-FRAMEWORK.md MONITORING-OPERATIONS-GUIDE.md; do
    if [[ -f "${vm_dir}/${f}" ]]; then
      sudo cp "${vm_dir}/${f}" "${workspace}/${f}"
      sudo chown "${oc_user}:${oc_user}" "${workspace}/${f}"
      print_success "Copied ${f} → ${workspace}/${f}"
    fi
  done
}

# ---------------------------------------------------------------------------
# Per-agent SOUL.md generation (for VM-3 and VM-4)
# ---------------------------------------------------------------------------
generate_agent_souls() {
  local vm_dir="$1"
  local prefix="$2"      # "dev" or "qc"
  local count="$3"
  local role_desc="$4"   # "Developer" or "QC Tester"
  local oc_user="${SUDO_USER:-$(whoami)}"
  local oc_home
  oc_home=$(eval echo "~${oc_user}")

  if [[ "$DRY_RUN" == "true" ]]; then
    print_warn "[DRY RUN] Would generate ${count} per-agent workspace + SOUL.md files"
    return
  fi

  for i in $(seq -f "%02g" 1 "$count"); do
    local agent_id="${prefix}-${i}"

    # Create per-agent workspace directory (~/.openclaw/workspace-dev-01, etc.)
    local agent_workspace="${oc_home}/.openclaw/workspace-${agent_id}"
    sudo -u "$oc_user" mkdir -p "$agent_workspace"

    # Create per-agent agentDir (~/.openclaw/agents/dev-01/agent)
    local agent_dir="${oc_home}/.openclaw/agents/${agent_id}/agent"
    sudo -u "$oc_user" mkdir -p "$agent_dir"

    # Copy shared config files to each agent workspace
    for f in AGENTS.md USER.md TOOLS.md; do
      if [[ -f "${vm_dir}/${f}" ]]; then
        sudo cp "${vm_dir}/${f}" "${agent_workspace}/${f}"
        sudo chown "${oc_user}:${oc_user}" "${agent_workspace}/${f}"
      fi
    done

    # Copy guideline docs to each agent workspace
    for f in BLUEPRINT-GUIDE.md RESILIENCE-SECURITY-GUIDE.md DEVELOPMENT-GUIDE.md QA-FRAMEWORK.md MONITORING-OPERATIONS-GUIDE.md; do
      if [[ -f "${vm_dir}/${f}" ]]; then
        sudo cp "${vm_dir}/${f}" "${agent_workspace}/${f}"
        sudo chown "${oc_user}:${oc_user}" "${agent_workspace}/${f}"
      fi
    done

    # Generate per-agent SOUL.md from template or create fresh
    if [[ -f "${vm_dir}/${prefix}-01/SOUL.md" ]]; then
      sed "s/${prefix}-01/${agent_id}/g" "${vm_dir}/${prefix}-01/SOUL.md" > "${agent_workspace}/SOUL.md"
    elif [[ -f "${vm_dir}/SOUL.md" ]]; then
      # Use the shared SOUL.md with agent ID injected
      sed "s/\${prefix}.*agent/${agent_id}/g" "${vm_dir}/SOUL.md" > "${agent_workspace}/SOUL.md"
    else
      cat > "${agent_workspace}/SOUL.md" << EOF
# ${role_desc} Agent — ${agent_id}

> GateForge Multi-Agent SDLC Pipeline — ${agent_id} (Port ${OPENCLAW_PORT})

## Identity

- **Agent ID**: ${agent_id}
- **Role**: ${role_desc}
- **Workspace**: ~/.openclaw/workspace-${agent_id}

## Behaviour

Follow the shared SOUL.md for this VM. This file defines your individual identity only.
All guidelines, tools, and communication protocols are inherited from the parent SOUL.md.
EOF
    fi
    sudo chown "${oc_user}:${oc_user}" "${agent_workspace}/SOUL.md"
    print_success "${agent_id}: workspace + SOUL.md + agentDir created"
  done

  print_success "${count} agent workspaces ready (${prefix}-01 to ${prefix}-$(printf '%02d' "$count"))"
}

# ---------------------------------------------------------------------------
# Enable webhooks in openclaw.json
# ---------------------------------------------------------------------------
enable_hooks() {
  local token="$1"
  local oc_user="${SUDO_USER:-$(whoami)}"
  local oc_home
  oc_home=$(eval echo "~${oc_user}")
  local oc_config="${oc_home}/.openclaw/openclaw.json"

  print_info "Enabling webhooks in ${oc_config}..."

  if [[ "$DRY_RUN" == "true" ]]; then
    print_warn "[DRY RUN] Would enable hooks in ${oc_config}"
    return
  fi

  if [[ ! -f "$oc_config" ]]; then
    print_error "OpenClaw config not found at ${oc_config}"
    print_info "Make sure OpenClaw is installed and has been started at least once."
    return 1
  fi

  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
try:
    with open('${oc_config}') as f:
        cfg = json.load(f)
    cfg['hooks'] = {
        'enabled': True,
        'token': '${token}',
        'path': '/hooks',
        'allowRequestSessionKey': True
    }
    with open('${oc_config}', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('ok')
except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
    if [[ $? -eq 0 ]]; then
      sudo chown "${oc_user}:${oc_user}" "$oc_config" 2>/dev/null || true
      print_success "Webhooks enabled in ${oc_config}"
    else
      print_error "Failed to update ${oc_config} — check JSON syntax"
      return 1
    fi
  elif command -v jq &>/dev/null; then
    local tmp_config
    tmp_config=$(mktemp)
    jq --arg token "$token" '.hooks = {enabled: true, token: $token, path: "/hooks", allowRequestSessionKey: true}' "$oc_config" > "$tmp_config" && mv "$tmp_config" "$oc_config"
    sudo chown "${oc_user}:${oc_user}" "$oc_config" 2>/dev/null || true
    print_success "Webhooks enabled in ${oc_config}"
  else
    print_error "Neither python3 nor jq found — cannot update ${oc_config} automatically"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Configure Gateway: bind=loopback, tailscale.mode=serve, Control UI origins
# ---------------------------------------------------------------------------
configure_gateway() {
  local ts_domain="$1"   # This VM's Tailscale domain (e.g. tonic-architect.sailfish-bass.ts.net)
  shift
  local all_ts_domains=("$@")  # All VM Tailscale domains for allowedOrigins
  local oc_user="${SUDO_USER:-$(whoami)}"
  local oc_home
  oc_home=$(eval echo "~${oc_user}")
  local oc_config="${oc_home}/.openclaw/openclaw.json"
  local port="${OPENCLAW_PORT:-18789}"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_warn "[DRY RUN] Would configure gateway: bind=loopback, tailscale.mode=serve"
    print_warn "[DRY RUN] Would set controlUi.allowedOrigins for ${#all_ts_domains[@]} Tailscale domains"
    return
  fi

  if [[ ! -f "$oc_config" ]]; then
    print_error "OpenClaw config not found at ${oc_config}"
    return 1
  fi

  # Build origins JSON array
  local origins_json='['
  local first=true
  for domain in "${all_ts_domains[@]}"; do
    [[ "$first" == "true" ]] && first=false || origins_json+=','
    origins_json+="\"https://${domain}:${port}\""
  done
  origins_json+=',"http://localhost:'"${port}"'","http://127.0.0.1:'"${port}"'"]'

  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys

config_path = '${oc_config}'
try:
    with open(config_path) as f:
        cfg = json.load(f)
except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)

# Configure gateway
gw = cfg.setdefault('gateway', {})

# bind: loopback (Tailscale Serve handles external access)
gw['bind'] = 'loopback'

# tailscale: serve mode
gw['tailscale'] = {
    'mode': 'serve',
    'resetOnExit': False
}

# controlUi: allow HTTPS from all Tailscale domains + localhost
cui = gw.setdefault('controlUi', {})
cui['allowInsecureAuth'] = True
new_origins = json.loads('${origins_json}')
existing = cui.get('allowedOrigins', [])
merged = list(dict.fromkeys(existing + new_origins))
cui['allowedOrigins'] = merged

with open(config_path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('ok')
" 2>/dev/null
    if [[ $? -eq 0 ]]; then
      sudo chown "${oc_user}:${oc_user}" "$oc_config" 2>/dev/null || true
      print_success "Gateway bind: loopback"
      print_success "Tailscale mode: serve"
      print_success "Control UI origins: ${#all_ts_domains[@]} Tailscale domains + localhost"
    else
      print_error "Failed to update gateway config in ${oc_config}"
      return 1
    fi
  else
    print_error "python3 required for gateway configuration"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Start Tailscale Serve (HTTPS proxy to local gateway)
# ---------------------------------------------------------------------------
start_tailscale_serve() {
  local port="${OPENCLAW_PORT:-18789}"
  local oc_user="${SUDO_USER:-$(whoami)}"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_warn "[DRY RUN] Would run: sudo tailscale serve --bg --https ${port} http://127.0.0.1:${port}"
    return
  fi

  print_info "Starting Tailscale Serve (HTTPS :${port} → http://127.0.0.1:${port})..."

  if ! command -v tailscale &>/dev/null; then
    print_error "tailscale not found — install Tailscale first"
    return 1
  fi

  if sudo tailscale serve --bg --https "${port}" "http://127.0.0.1:${port}" 2>/dev/null; then
    print_success "Tailscale Serve running in background"
    # Show the Tailscale domain for reference
    local ts_status
    ts_status=$(tailscale status --self --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin)['Self']; print(d.get('DNSName','').rstrip('.'))" 2>/dev/null || echo "")
    if [[ -n "$ts_status" ]]; then
      print_success "Accessible at: https://${ts_status}:${port}"
    fi
  else
    print_warn "Could not start Tailscale Serve automatically"
    echo -e "  ${DIM}Run manually: sudo tailscale serve --bg --https ${port} http://127.0.0.1:${port}${RESET}"
  fi
}

# ---------------------------------------------------------------------------
# Device pairing (approve the latest device)
# ---------------------------------------------------------------------------
pair_device() {
  local oc_user="${SUDO_USER:-$(whoami)}"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_warn "[DRY RUN] Would prompt for device pairing"
    return
  fi

  print_info "Checking for devices pending approval..."

  # List devices
  if sudo -u "$oc_user" openclaw devices list 2>/dev/null; then
    echo ""
    echo -en "  ${BOLD}Approve the latest device now?${RESET} [${DIM}Y/n${RESET}]: "
    read -r answer
    if [[ "${answer,,}" != "n" ]]; then
      if sudo -u "$oc_user" openclaw devices approve --latest 2>/dev/null; then
        print_success "Device approved"
      else
        print_warn "No pending devices or approval failed"
        echo -e "  ${DIM}Run manually: openclaw devices list && openclaw devices approve --latest${RESET}"
      fi
    fi
  else
    print_warn "Could not list devices — gateway may not be running yet"
    echo -e "  ${DIM}After starting the gateway, run:${RESET}"
    echo -e "  ${DIM}  openclaw devices list${RESET}"
    echo -e "  ${DIM}  openclaw devices approve --latest${RESET}"
  fi
}

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
verify_openclaw() {
  print_info "Checking OpenClaw gateway..."
  if command -v openclaw &>/dev/null; then
    print_success "OpenClaw found: $(command -v openclaw)"
  else
    print_warn "'openclaw' not found in PATH (may be installed under a different name or path — skipping check)"
  fi

  # Check gateway is listening
  local bind_check
  bind_check=$(ss -tlnp 2>/dev/null | grep ":18789" | head -1 || true)
  if echo "$bind_check" | grep -q "127\.0\.0\.1"; then
    print_success "Gateway listening on 127.0.0.1:18789 (loopback — Tailscale Serve provides external HTTPS access)"
  elif [[ -n "$bind_check" ]]; then
    print_success "Gateway listening on port 18789"
  else
    print_warn "Port 18789 not listening — gateway may not be running"
  fi
}

setup_firewall() {
  print_info "Configuring UFW firewall..."

  if ! command -v ufw &>/dev/null; then
    print_warn "UFW not installed — skipping firewall setup"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    print_warn "[DRY RUN] Would configure UFW to allow Tailscale interface"
    return
  fi

  sudo ufw default deny incoming 2>/dev/null || true
  sudo ufw default allow outgoing 2>/dev/null || true
  sudo ufw allow ssh 2>/dev/null || true

  # Allow gateway port from anything on the Tailscale interface (tailscale0).
  # This is robust against IP changes — only Tailscale peers can reach 18789.
  if ip link show tailscale0 &>/dev/null; then
    sudo ufw allow in on tailscale0 to any port 18789 proto tcp 2>/dev/null || true
    print_success "UFW: allowed port 18789 on tailscale0"
  else
    print_warn "tailscale0 interface not found — falling back to allowing the 100.64.0.0/10 CGNAT range"
    sudo ufw allow from 100.64.0.0/10 to any port 18789 2>/dev/null || true
  fi

  # Enable UFW (non-interactive)
  echo "y" | sudo ufw enable 2>/dev/null || true
  print_success "UFW configured — port 18789 reachable only via Tailscale"
}

verify_connectivity() {
  local target_domain="$1"
  local target_port="$2"
  local label="$3"

  # Tailscale Serve fronts the gateway with HTTPS using a MagicDNS cert.
  # We dial https://<domain>:<port> — not http://<ip>:<port>.
  if curl -sf --max-time 3 "https://${target_domain}:${target_port}/health" &>/dev/null 2>&1; then
    print_success "${label}: reachable"
  else
    print_warn "${label}: not reachable (may not be running yet)"
  fi
}

# ---------------------------------------------------------------------------
# Install the host-side notifier (spokes only): systemd path + service +
# the dispatcher script. Wraps install/install-host-notifier.sh.
# ---------------------------------------------------------------------------
install_host_notifier_hook() {
  local script_dir="${1:-${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}}"
  local installer="${script_dir}/install-host-notifier.sh"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_warn "[DRY RUN] Would run ${installer}"
    return
  fi

  if [[ ! -f "$installer" ]]; then
    print_error "Host notifier installer not found: ${installer}"
    return 1
  fi

  print_info "Installing host-side notifier (gf-notify-architect)..."
  if sudo bash "$installer"; then
    print_success "Host notifier installed and active (watch /opt/gateforge/blueprint/.git/refs)"
  else
    print_error "Host notifier install failed"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Summary display
# ---------------------------------------------------------------------------
print_summary_box() {
  local title="$1"
  shift
  local width=64

  echo ""
  echo -e "  ${TEAL}┌$(printf '─%.0s' $(seq 1 $width))┐${RESET}"
  echo -e "  ${TEAL}│${RESET} ${BOLD}${title}$(printf ' %.0s' $(seq 1 $((width - ${#title} - 1))))${TEAL}│${RESET}"
  echo -e "  ${TEAL}├$(printf '─%.0s' $(seq 1 $width))┤${RESET}"

  while [[ $# -gt 0 ]]; do
    local label="$1"
    local value="$2"
    shift 2
    local line="${label} ${value}"
    local padding=$((width - ${#line} - 1))
    if (( padding < 0 )); then padding=0; fi
    echo -e "  ${TEAL}│${RESET} ${DIM}${label}${RESET} ${value}$(printf ' %.0s' $(seq 1 $padding))${TEAL}│${RESET}"
  done

  echo -e "  ${TEAL}└$(printf '─%.0s' $(seq 1 $width))┘${RESET}"
  echo ""
}

mask_secret() {
  local s="$1"
  if [[ ${#s} -gt 12 ]]; then
    echo "${s:0:6}...${s: -4}"
  else
    echo "****"
  fi
}

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------
parse_common_flags() {
  for arg in "$@"; do
    case "$arg" in
      --help|-h) return 1 ;;
      --dry-run) DRY_RUN="true"; print_warn "DRY RUN MODE — no changes will be made" ;;
    esac
  done
  return 0
}
