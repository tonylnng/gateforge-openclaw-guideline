#!/usr/bin/env bash
# =============================================================================
# GateForge Communication Setup — VM-1: System Architect
# =============================================================================
# Assumes OpenClaw is already installed with API key and Telegram configured.
# This script sets up inter-agent communication tokens, secrets, and IPs.
# Run this FIRST — it generates secrets for all spoke VMs.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/install-common.sh"

TOTAL_STEPS=11
VM_NAME="vm1"
VM_ROLE="VM-1: System Architect"
VM_DIR="${SCRIPT_DIR}/vm-1-architect"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
show_help() {
  print_banner
  echo -e "  ${BOLD}Usage:${RESET} sudo bash setup-vm1-architect.sh [--help] [--dry-run]"
  echo ""
  echo -e "  ${BOLD}VM-1: System Architect${RESET} — Hub coordinator"
  echo -e "  Assumes OpenClaw is already installed with API key and Telegram."
  echo ""
  echo -e "  ${BOLD}This script will:${RESET}"
  echo -e "    1. Verify OpenClaw is installed"
  echo -e "    2. Prompt for VM IPs / Tailscale hostnames"
  echo -e "    3. Generate gateway tokens and HMAC secrets for all 5 VMs"
  echo -e "    4. Write central config to ${CONFIG_FILE}"
  echo -e "    5. Copy GateForge config files (SOUL.md, AGENTS.md, etc.)"
  echo -e "    6. Display all secrets for spoke VM setup"
  echo ""
  echo -e "  ${BOLD}Options:${RESET}"
  echo -e "    --help      Show this help message"
  echo -e "    --dry-run   Show what would be done without making changes"
  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  if ! parse_common_flags "$@"; then
    show_help
    exit 0
  fi

  print_banner
  echo -e "  ${BOLD}Setting up: ${TEAL}${VM_ROLE}${RESET}"
  echo -e "  ${DIM}This VM is the hub — run this script FIRST.${RESET}"
  echo ""

  # --- Step 1: Verify OpenClaw ---
  print_step "Verify OpenClaw Installation"
  verify_openclaw

  # Load existing config if present
  if load_existing_config; then
    print_info "Pre-filling values from existing config."
    confirm_continue "Overwrite existing config?"
  fi

  # --- Step 2: Network ---
  print_step "Verify Network & Firewall"
  setup_firewall

  # --- Step 3: Collect IPs ---
  TOTAL_STEPS=11
  print_step "Configure VM Addresses"
  echo -e "  ${DIM}Enter Tailscale domain names for each VM (e.g. tonic-architect.sailfish-bass.ts.net)${RESET}"
  echo -e "  ${DIM}These are used for HTTPS communication via Tailscale Serve.${RESET}"
  echo ""

  prompt_required VM1_TS_DOMAIN  "VM-1 Architect Tailscale domain"  "${VM1_TS_DOMAIN:-tonic-architect.sailfish-bass.ts.net}"
  prompt_required VM2_TS_DOMAIN  "VM-2 Designer Tailscale domain"   "${VM2_TS_DOMAIN:-tonic-designer.sailfish-bass.ts.net}"
  prompt_required VM3_TS_DOMAIN  "VM-3 Developers Tailscale domain" "${VM3_TS_DOMAIN:-tonic-developer.sailfish-bass.ts.net}"
  prompt_required VM4_TS_DOMAIN  "VM-4 QC Agents Tailscale domain"  "${VM4_TS_DOMAIN:-tonic-qc.sailfish-bass.ts.net}"
  prompt_required VM5_TS_DOMAIN  "VM-5 Operator Tailscale domain"   "${VM5_TS_DOMAIN:-tonic-operator.sailfish-bass.ts.net}"

  # --- Step 3: Generate tokens and secrets ---
  print_step "Generate Tokens & HMAC Secrets"

  # Check if we have existing tokens from a previous run
  local has_existing_tokens=false
  if [[ -n "${GATEWAY_AUTH_TOKEN:-}" && -n "${VM2_GATEWAY_TOKEN:-}" ]]; then
    has_existing_tokens=true
  fi

  if [[ "$has_existing_tokens" == "true" ]]; then
    echo ""
    echo -e "  ${YELLOW}${BOLD}Existing tokens detected from previous setup.${RESET}"
    echo -e "  ${DIM}Regenerating tokens will require re-running setup on ALL spoke VMs.${RESET}"
    echo ""
    echo -e "  ${BOLD}Choose an option:${RESET}"
    echo -e "    ${TEAL}1)${RESET} Keep existing tokens (recommended if spokes are already configured)"
    echo -e "    ${TEAL}2)${RESET} Regenerate ALL tokens (you must re-setup every spoke VM)"
    echo -e "    ${TEAL}3)${RESET} Choose per token (keep some, regenerate others)"
    echo ""
    local token_choice=""
    while [[ ! "$token_choice" =~ ^[123]$ ]]; do
      echo -en "  ${BOLD}Choose [1-3]${RESET}: "
      read -r token_choice
      [[ ! "$token_choice" =~ ^[123]$ ]] && print_error "Invalid choice."
    done
  else
    # No existing tokens — generate everything fresh
    local token_choice="2"
    echo -e "  ${DIM}No existing tokens found — generating fresh tokens.${RESET}"
  fi

  echo ""

  # --- Helper: keep or regenerate a single token ---
  keep_or_regen() {
    local var_name="$1"
    local label="$2"
    local current_value="${!var_name:-}"

    case "$token_choice" in
      1)  # Keep all existing
        if [[ -n "$current_value" ]]; then
          eval "$var_name='$current_value'"
          print_success "${label}: kept existing ($(mask_secret "$current_value"))"
        else
          local new_val
          new_val=$(generate_secret)
          eval "$var_name='$new_val'"
          print_success "${label}: generated new (no existing value)"
        fi
        ;;
      2)  # Regenerate all
        local new_val
        new_val=$(generate_secret)
        eval "$var_name='$new_val'"
        print_success "${label}: generated new"
        ;;
      3)  # Ask per token
        if [[ -n "$current_value" ]]; then
          echo -en "  ${BOLD}${label}${RESET} — keep existing ($(mask_secret "$current_value"))? [${DIM}Y/n${RESET}]: "
          read -r answer
          if [[ "${answer,,}" == "n" ]]; then
            local new_val
            new_val=$(generate_secret)
            eval "$var_name='$new_val'"
            print_success "${label}: regenerated"
          else
            eval "$var_name='$current_value'"
            print_success "${label}: kept existing"
          fi
        else
          local new_val
          new_val=$(generate_secret)
          eval "$var_name='$new_val'"
          print_success "${label}: generated new (no existing value)"
        fi
        ;;
    esac
  }

  # --- VM-1 own tokens ---
  echo -e "  ${BOLD}VM-1 Architect tokens:${RESET}"
  keep_or_regen GATEWAY_AUTH_TOKEN    "Gateway auth token"
  keep_or_regen ARCHITECT_HOOK_TOKEN  "Architect hook token"

  # --- Spoke gateway tokens ---
  echo ""
  echo -e "  ${BOLD}Spoke gateway tokens:${RESET}"
  keep_or_regen VM2_GATEWAY_TOKEN  "VM-2 Designer gateway token"
  keep_or_regen VM3_GATEWAY_TOKEN  "VM-3 Developers gateway token"
  keep_or_regen VM4_GATEWAY_TOKEN  "VM-4 QC Agents gateway token"
  keep_or_regen VM5_GATEWAY_TOKEN  "VM-5 Operator gateway token"

  # --- Spoke HMAC secrets ---
  echo ""
  echo -e "  ${BOLD}Spoke HMAC signing secrets:${RESET}"
  keep_or_regen VM2_AGENT_SECRET  "VM-2 Designer HMAC secret"
  keep_or_regen VM3_AGENT_SECRET  "VM-3 Developers HMAC secret"
  keep_or_regen VM4_AGENT_SECRET  "VM-4 QC Agents HMAC secret"
  keep_or_regen VM5_AGENT_SECRET  "VM-5 Operator HMAC secret"

  # --- Step 4: Write central config ---
  print_step "Write Central Config File"

  local config_content
  config_content=$(cat << EOF
# =============================================================================
# GateForge Central Configuration — VM-1: System Architect
# =============================================================================
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# This file is loaded by the OpenClaw agent for inter-VM communication.
# Permissions: root:root 600 — do NOT commit to Git.
# =============================================================================

# --- This VM ---
GATEFORGE_ROLE=architect
GATEFORGE_VM_HOST=${VM1_TS_DOMAIN}
GATEFORGE_PORT=${OPENCLAW_PORT}
GATEWAY_AUTH_TOKEN=${GATEWAY_AUTH_TOKEN}

# --- Architect Hook (inbound notifications from spokes) ---
ARCHITECT_HOOK_TOKEN=${ARCHITECT_HOOK_TOKEN}
ARCHITECT_NOTIFY_URL=https://${VM1_TS_DOMAIN}:${OPENCLAW_PORT}/hooks/agent

# --- Communication Test Target ---
# Throwaway repo used by install/test-communication.sh. Spokes push test
# branches here; the test script deletes them after each run.
COMMTEST_REPO_URL=${COMMTEST_REPO_URL}

# --- Tailscale Domains ---
VM1_TS_DOMAIN=${VM1_TS_DOMAIN}
VM2_TS_DOMAIN=${VM2_TS_DOMAIN}
VM3_TS_DOMAIN=${VM3_TS_DOMAIN}
VM4_TS_DOMAIN=${VM4_TS_DOMAIN}
VM5_TS_DOMAIN=${VM5_TS_DOMAIN}

# --- VM-2: System Designer ---
VM2_GATEWAY_TOKEN=${VM2_GATEWAY_TOKEN}
VM2_AGENT_SECRET=${VM2_AGENT_SECRET}

# --- VM-3: Developers ---
VM3_GATEWAY_TOKEN=${VM3_GATEWAY_TOKEN}
VM3_AGENT_SECRET=${VM3_AGENT_SECRET}

# --- VM-4: QC Agents ---
VM4_GATEWAY_TOKEN=${VM4_GATEWAY_TOKEN}
VM4_AGENT_SECRET=${VM4_AGENT_SECRET}

# --- VM-5: Operator ---
VM5_GATEWAY_TOKEN=${VM5_GATEWAY_TOKEN}
VM5_AGENT_SECRET=${VM5_AGENT_SECRET}
EOF
)

  write_config "$config_content"

  # --- Step 5: Copy config files ---
  print_step "Copy GateForge Config Files"
  copy_config_files "$VM_DIR"

  # --- Step 6: Enable webhooks ---
  print_step "Enable Webhooks in OpenClaw"
  enable_hooks "$ARCHITECT_HOOK_TOKEN"

  # --- Step 6b: Create hook log directory ---
  print_step "Prepare Hook Log Directory"
  local oc_user="${SUDO_USER:-$(whoami)}"
  local hook_log_dir="/var/log/gateforge"
  if sudo mkdir -p "$hook_log_dir"; then
    sudo chown "${oc_user}:${oc_user}" "$hook_log_dir"
    sudo chmod 755 "$hook_log_dir"
    # Pre-create the file so test-communication.sh's tail can attach immediately
    sudo -u "$oc_user" touch "${hook_log_dir}/architect-hook.log"
    print_success "Hook log dir ready: ${hook_log_dir}"
  else
    print_warn "Could not create ${hook_log_dir} (test-communication.sh will fall back to ~/.openclaw/logs)"
  fi

  # --- Step 7: Configure Gateway (loopback + Tailscale Serve) ---
  print_step "Configure Gateway & Tailscale"
  configure_gateway "$VM1_TS_DOMAIN" \
    "$VM1_TS_DOMAIN" "$VM2_TS_DOMAIN" "$VM3_TS_DOMAIN" "$VM4_TS_DOMAIN" "$VM5_TS_DOMAIN"

  # --- Step 8: Start Tailscale Serve ---
  print_step "Start Tailscale Serve"
  start_tailscale_serve

  # --- Step 9: Restart Gateway & Pair Device ---
  print_step "Restart Gateway & Device Pairing"
  local oc_user="${SUDO_USER:-$(whoami)}"
  print_info "Restarting OpenClaw gateway..."
  if sudo -u "$oc_user" openclaw gateway restart &>/dev/null 2>&1; then
    print_success "Gateway restarted"
  else
    print_warn "Could not restart gateway. Run: openclaw gateway restart"
  fi
  pair_device

  # --- Step 10: Summary ---
  print_step "Setup Complete"

  print_summary_box "VM-1 System Architect — Configuration" \
    "Role:" "System Architect (Hub)" \
    "Host:" "$VM1_TS_DOMAIN" \
    "Port:" "$OPENCLAW_PORT" \
    "Config:" "$CONFIG_FILE" \
    "Gateway Token:" "$(mask_secret "$GATEWAY_AUTH_TOKEN")" \
    "Hook Token:" "$(mask_secret "$ARCHITECT_HOOK_TOKEN")"

  # Display spoke secrets — the user needs these for spoke VM setup
  echo -e "  ${RED}${BOLD}┌────────────────────────────────────────────────────────────────┐${RESET}"
  echo -e "  ${RED}${BOLD}│  SAVE THESE VALUES — needed when setting up spoke VMs         │${RESET}"
  echo -e "  ${RED}${BOLD}├────────────────────────────────────────────────────────────────┤${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}                                                                ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}  ${BOLD}Architect Hook Token (all spokes need this):${RESET}                 ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}  ${TEAL}${ARCHITECT_HOOK_TOKEN}${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}                                                                ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}  ${BOLD}VM-2 Designer:${RESET}                                              ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}    Gateway Token: ${TEAL}${VM2_GATEWAY_TOKEN}${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}    HMAC Secret:   ${TEAL}${VM2_AGENT_SECRET}${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}                                                                ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}  ${BOLD}VM-3 Developers:${RESET}                                            ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}    Gateway Token: ${TEAL}${VM3_GATEWAY_TOKEN}${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}    HMAC Secret:   ${TEAL}${VM3_AGENT_SECRET}${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}                                                                ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}  ${BOLD}VM-4 QC Agents:${RESET}                                             ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}    Gateway Token: ${TEAL}${VM4_GATEWAY_TOKEN}${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}    HMAC Secret:   ${TEAL}${VM4_AGENT_SECRET}${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}                                                                ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}  ${BOLD}VM-5 Operator:${RESET}                                              ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}    Gateway Token: ${TEAL}${VM5_GATEWAY_TOKEN}${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}    HMAC Secret:   ${TEAL}${VM5_AGENT_SECRET}${RESET}"
  echo -e "  ${RED}${BOLD}│${RESET}                                                                ${RED}${BOLD}│${RESET}"
  echo -e "  ${RED}${BOLD}└────────────────────────────────────────────────────────────────┘${RESET}"
  echo ""
  echo -e "  ${GREEN}${BOLD}VM-1 Architect setup complete.${RESET}"
  echo -e "  Now run the setup script on each spoke VM and paste the values above."
  echo ""
}

main "$@"
