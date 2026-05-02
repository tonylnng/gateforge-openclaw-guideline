#!/usr/bin/env bash
# =============================================================================
# GateForge Communication Setup — VM-3: Developers
# =============================================================================
# Assumes OpenClaw is already installed with API key configured.
# Also asks how many Developer agents to create (3, 5, or 10).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/install-common.sh"

TOTAL_STEPS=11
VM_NAME="vm3"
VM_NUM=3
VM_ROLE="VM-3: Developers"
VM_DIR="${SCRIPT_DIR}/vm-3-developers"

show_help() {
  print_banner
  echo -e "  ${BOLD}Usage:${RESET} sudo bash setup-vm3-developers.sh [--help] [--dry-run]"
  echo ""
  echo -e "  ${BOLD}VM-3: Developers${RESET} — Multi-agent spoke"
  echo -e "  Sets up communication + generates per-agent SOUL.md files."
  echo ""
  echo -e "  ${BOLD}This script will:${RESET}"
  echo -e "    1. Verify OpenClaw is installed"
  echo -e "    2. Prompt for connection details (from VM-1 output)"
  echo -e "    3. Ask how many Developer agents (3, 5, or 10)"
  echo -e "    4. Write central config to ${CONFIG_FILE}"
  echo -e "    5. Copy GateForge config files + generate per-agent SOUL.md"
  echo -e "    6. Verify connectivity"
  echo ""
}

main() {
  if ! parse_common_flags "$@"; then
    show_help
    exit 0
  fi

  print_banner
  echo -e "  ${BOLD}Setting up: ${TEAL}${VM_ROLE}${RESET}"
  echo ""

  # --- Step 1: Verify ---
  print_step "Verify OpenClaw Installation"
  verify_openclaw
  if load_existing_config; then
    confirm_continue "Overwrite existing config?"
  fi

  # --- Step 2: Network ---
  print_step "Verify Network & Firewall"
  setup_firewall

  # --- Step 3: Collect config ---
  print_step "Configure Communication"

  prompt_required VM3_TS_DOMAIN       "This VM's Tailscale domain"  "${VM3_TS_DOMAIN:-tonic-developer.sailfish-bass.ts.net}"
  prompt_required ARCHITECT_TS_DOMAIN "Architect Tailscale domain"  "${ARCHITECT_TS_DOMAIN:-tonic-architect.sailfish-bass.ts.net}"
  echo ""
  echo -e "  ${DIM}Paste the remaining Tailscale domains (for Control UI origins):${RESET}"
  prompt_required VM2_TS_DOMAIN  "VM-2 Designer Tailscale domain" "${VM2_TS_DOMAIN:-tonic-designer.sailfish-bass.ts.net}"
  prompt_required VM4_TS_DOMAIN  "VM-4 QC Agents Tailscale domain" "${VM4_TS_DOMAIN:-tonic-qc.sailfish-bass.ts.net}"
  prompt_required VM5_TS_DOMAIN  "VM-5 Operator Tailscale domain" "${VM5_TS_DOMAIN:-tonic-operator.sailfish-bass.ts.net}"
  echo ""
  echo -e "  ${DIM}Paste these from the VM-1 Architect setup output:${RESET}"
  prompt_required GATEWAY_AUTH_TOKEN  "This VM's gateway token"    "${GATEWAY_AUTH_TOKEN:-}"
  prompt_required ARCHITECT_HOOK_TOKEN "Architect hook token"      "${ARCHITECT_HOOK_TOKEN:-}"
  prompt_required AGENT_SECRET        "This VM's HMAC secret"     "${AGENT_SECRET:-}"

  # --- Step 3: Agent count ---
  print_step "Configure Developer Agents"
  prompt_choice AGENT_COUNT "How many Developer agents?" "3" "5" "10"
  print_info "Will create ${AGENT_COUNT} Developer agents (dev-01 through dev-$(printf '%02d' "$AGENT_COUNT"))"

  # --- Step 4: Write config ---
  print_step "Write Central Config File"

  local config_content
  config_content=$(cat << EOF
# =============================================================================
# GateForge Central Configuration — VM-3: Developers
# =============================================================================
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Permissions: root:root 600 — do NOT commit to Git.
# =============================================================================

# --- This VM ---
GATEFORGE_ROLE=developers
GATEFORGE_VM_NUM=${VM_NUM}
GATEFORGE_VM_HOST=${VM3_TS_DOMAIN}
GATEFORGE_PORT=${OPENCLAW_PORT}
GATEWAY_AUTH_TOKEN=${GATEWAY_AUTH_TOKEN}
AGENT_COUNT=${AGENT_COUNT}

# --- Architect Connection ---
ARCHITECT_NOTIFY_URL=https://${ARCHITECT_TS_DOMAIN}:${OPENCLAW_PORT}/hooks/agent
ARCHITECT_TS_DOMAIN=${ARCHITECT_TS_DOMAIN}
VM3_TS_DOMAIN=${VM3_TS_DOMAIN}
VM2_TS_DOMAIN=${VM2_TS_DOMAIN}
VM4_TS_DOMAIN=${VM4_TS_DOMAIN}
VM5_TS_DOMAIN=${VM5_TS_DOMAIN}
ARCHITECT_HOOK_TOKEN=${ARCHITECT_HOOK_TOKEN}

# --- HMAC Signing Secret (never transmitted) ---
AGENT_SECRET=${AGENT_SECRET}

# --- Communication Test Target ---
# Throwaway repo used by install/test-communication.sh on VM-1. The spoke
# agent reads this to know which remote to push test branches to. Not used
# by any project — comm test only.
COMMTEST_REPO_URL=${COMMTEST_REPO_URL}
EOF
)

  write_config "$config_content"

  # --- Step 5: Copy config files + generate agent SOULs ---
  print_step "Copy Config Files & Generate Agent Identities"
  copy_config_files "$VM_DIR"
  generate_agent_souls "$VM_DIR" "dev" "$AGENT_COUNT" "Developer"

  # --- Step 5c: Install host-side notifier ---
  print_step "Install Host-Side Notifier"
  install_host_notifier_hook "$SCRIPT_DIR"

  # --- Step 6: Enable webhooks ---
  print_step "Enable Webhooks in OpenClaw"
  enable_hooks "$GATEWAY_AUTH_TOKEN"

  # --- Step 6: Configure Gateway (loopback + Tailscale Serve) ---
  print_step "Configure Gateway & Tailscale"
  configure_gateway "$VM3_TS_DOMAIN" \
    "$ARCHITECT_TS_DOMAIN" "$VM3_TS_DOMAIN" "$VM2_TS_DOMAIN" "$VM4_TS_DOMAIN" "$VM5_TS_DOMAIN"

  # --- Step 7: Start Tailscale Serve ---
  print_step "Start Tailscale Serve"
  start_tailscale_serve

  # --- Step 8: Restart Gateway & Pair Device ---
  print_step "Restart Gateway & Device Pairing"
  local oc_user="${SUDO_USER:-$(whoami)}"
  print_info "Restarting OpenClaw gateway..."
  if sudo -u "$oc_user" openclaw gateway restart &>/dev/null 2>&1; then
    print_success "Gateway restarted"
  else
    print_warn "Could not restart gateway. Run: openclaw gateway restart"
  fi
  pair_device

  # --- Step 10: Verify ---
  print_step "Verify & Summary"
  verify_connectivity "$ARCHITECT_TS_DOMAIN" "$OPENCLAW_PORT" "Architect (${ARCHITECT_TS_DOMAIN})"

  print_summary_box "VM-3 Developers — Configuration" \
    "Role:" "Developers (Spoke)" \
    "Host:" "$VM3_TS_DOMAIN" \
    "Agent Count:" "$AGENT_COUNT (dev-01 to dev-$(printf '%02d' "$AGENT_COUNT"))" \
    "Config:" "$CONFIG_FILE" \
    "Architect:" "https://${ARCHITECT_TS_DOMAIN}:${OPENCLAW_PORT}" \
    "Gateway Token:" "$(mask_secret "$GATEWAY_AUTH_TOKEN")" \
    "HMAC Secret:" "$(mask_secret "$AGENT_SECRET")"

  echo -e "  ${GREEN}${BOLD}VM-3 Developers setup complete.${RESET}"
  echo ""
}

main "$@"
