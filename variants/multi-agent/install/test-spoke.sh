#!/usr/bin/env bash
# =============================================================================
# GateForge — Spoke VM Connectivity Test
# =============================================================================
# Run this on ANY spoke VM (VM-2 through VM-5) to test its connection
# to the Architect via Tailscale HTTPS domains.
# Uses the local /opt/secrets/gateforge.env config.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
TEAL='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PASS=0
FAIL=0
WARN=0

CONFIG_FILE="/opt/secrets/gateforge.env"

result_pass() { echo -e "  ${GREEN}✓ PASS${RESET}  $1"; PASS=$((PASS + 1)); }
result_fail() { echo -e "  ${RED}✗ FAIL${RESET}  $1"; FAIL=$((FAIL + 1)); }
result_warn() { echo -e "  ${YELLOW}! WARN${RESET}  $1"; WARN=$((WARN + 1)); }
print_header() { echo ""; echo -e "${TEAL}${BOLD}═══ $1 ═══${RESET}"; }

# ---------------------------------------------------------------------------
echo ""
echo -e "${TEAL}${BOLD}  GateForge — Spoke Connectivity Test${RESET}"
echo -e "  ${DIM}Run on any spoke VM (VM-2 through VM-5)${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------
print_header "Loading Configuration"

if [[ ! -f "$CONFIG_FILE" ]]; then
  result_fail "Config file not found: ${CONFIG_FILE}"
  echo -e "\n  Run the setup script for this VM first."
  exit 1
fi

eval "$(sudo cat "$CONFIG_FILE" | grep -v '^#' | grep '=')" 2>/dev/null
result_pass "Loaded ${CONFIG_FILE}"

ROLE="${GATEFORGE_ROLE:-unknown}"
PORT="${GATEFORGE_PORT:-18789}"
ARCHITECT_DOMAIN="${ARCHITECT_TS_DOMAIN:-}"
HOOK_TOKEN="${ARCHITECT_HOOK_TOKEN:-}"
NOTIFY_URL="${ARCHITECT_NOTIFY_URL:-}"
SECRET="${AGENT_SECRET:-}"
GW_TOKEN="${GATEWAY_AUTH_TOKEN:-}"

echo -e "  ${DIM}Role:      ${ROLE}${RESET}"
echo -e "  ${DIM}This VM:   $(hostname) (loopback gateway)${RESET}"
echo -e "  ${DIM}Architect: ${ARCHITECT_DOMAIN}:${PORT}${RESET}"

# Check required vars
MISSING=0
for var in ARCHITECT_DOMAIN HOOK_TOKEN NOTIFY_URL SECRET GW_TOKEN; do
  if [[ -z "${!var}" ]]; then
    result_fail "Missing: ${var}"
    MISSING=$((MISSING + 1))
  fi
done

if [[ $MISSING -gt 0 ]]; then
  echo ""
  echo -e "  ${YELLOW}Required variables are missing from ${CONFIG_FILE}.${RESET}"
  echo -e "  ${DIM}Re-run the setup script for this VM to populate them.${RESET}"
fi

# ---------------------------------------------------------------------------
# Pre-flight: Verify webhooks are enabled in openclaw.json
# ---------------------------------------------------------------------------
print_header "Pre-flight: Webhook Configuration"

# Resolve the OpenClaw user — the user running OpenClaw (not root)
OC_USER="${GATEFORGE_SSH_USER:-${SUDO_USER:-$(whoami)}}"
OC_HOME=$(eval echo "~${OC_USER}")
OC_CONFIG="${OC_HOME}/.openclaw/openclaw.json"

HOOKS_OK_LOCAL=false
HOOKS_OK_ARCHITECT=false

# --- Check local spoke VM ---
if [[ -f "$OC_CONFIG" ]]; then
  if command -v python3 &>/dev/null; then
    HOOKS_ENABLED=$(python3 -c "
import json, sys
try:
    with open('${OC_CONFIG}') as f:
        cfg = json.load(f)
    enabled = cfg.get('hooks', {}).get('enabled', False)
    token = cfg.get('hooks', {}).get('token', '')
    print(f'{enabled}|{len(token) > 0}')
except: print('error|error')
" 2>/dev/null || echo "error|error")
    H_ENABLED="${HOOKS_ENABLED%%|*}"
    H_HAS_TOKEN="${HOOKS_ENABLED##*|}"
  else
    if grep -q '"enabled".*true' "$OC_CONFIG" 2>/dev/null; then H_ENABLED="True"; else H_ENABLED="False"; fi
    if grep -q '"token"' "$OC_CONFIG" 2>/dev/null; then H_HAS_TOKEN="True"; else H_HAS_TOKEN="False"; fi
  fi

  if [[ "$H_ENABLED" == "True" && "$H_HAS_TOKEN" == "True" ]]; then
    result_pass "Local (${ROLE}) — webhooks enabled with token in ${OC_CONFIG}"
    HOOKS_OK_LOCAL=true
  elif [[ "$H_ENABLED" == "True" && "$H_HAS_TOKEN" != "True" ]]; then
    result_fail "Local (${ROLE}) — hooks.enabled=true but hooks.token is missing"
  elif [[ "$H_ENABLED" == "error" ]]; then
    result_warn "Local (${ROLE}) — could not parse ${OC_CONFIG} (check JSON syntax)"
  else
    result_fail "Local (${ROLE}) — webhooks NOT enabled in ${OC_CONFIG}"
    echo -e "  ${DIM}Fix: Add to ${OC_CONFIG}:${RESET}"
    echo -e "  ${DIM}  { \"hooks\": { \"enabled\": true, \"token\": \"<GATEWAY_AUTH_TOKEN>\", \"path\": \"/hooks\" } }${RESET}"
    echo -e "  ${DIM}Then: openclaw daemon restart${RESET}"
  fi
else
  result_fail "Local (${ROLE}) — ${OC_CONFIG} not found"
  echo -e "  ${DIM}Expected OpenClaw config at: ${OC_CONFIG}${RESET}"
  echo -e "  ${DIM}Detected user: ${OC_USER} (override with GATEFORGE_SSH_USER env var)${RESET}"
fi

# --- Probe Architect hook endpoint via Tailscale HTTPS ---
if [[ -n "$ARCHITECT_DOMAIN" ]]; then
  ARCH_PROBE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${ARCHITECT_DOMAIN}:${PORT}/hooks/agent" 2>/dev/null || echo "000")
  if [[ "$ARCH_PROBE" == "405" || "$ARCH_PROBE" == "200" || "$ARCH_PROBE" == "401" ]]; then
    result_pass "Architect (${ARCHITECT_DOMAIN}) — /hooks/agent endpoint exists (HTTPS ${ARCH_PROBE})"
    HOOKS_OK_ARCHITECT=true
  elif [[ "$ARCH_PROBE" == "404" ]]; then
    result_fail "Architect (${ARCHITECT_DOMAIN}) — /hooks/agent returns 404 (webhooks not enabled on Architect VM)"
    echo -e "  ${DIM}Fix: On VM-1, ensure ~/.openclaw/openclaw.json has hooks.enabled=true${RESET}"
    echo -e "  ${DIM}Then: openclaw daemon restart${RESET}"
  elif [[ "$ARCH_PROBE" == "000" ]]; then
    result_warn "Architect (${ARCHITECT_DOMAIN}) — could not connect (will be tested in Test 1/2)"
  else
    result_warn "Architect (${ARCHITECT_DOMAIN}) — /hooks/agent probe returned HTTPS ${ARCH_PROBE}"
  fi
else
  result_warn "Architect domain not set — skipping probe"
fi

if [[ "$HOOKS_OK_LOCAL" != "true" || "$HOOKS_OK_ARCHITECT" != "true" ]]; then
  echo ""
  echo -e "  ${YELLOW}${BOLD}Webhook tests (4-5) will fail until hooks are enabled.${RESET}"
  echo -e "  ${YELLOW}Continuing with remaining tests...${RESET}"
fi

# ---------------------------------------------------------------------------
# Test 1: Tailscale Ping Architect
# ---------------------------------------------------------------------------
print_header "Test 1: Network — Tailscale Ping Architect"

if [[ -n "$ARCHITECT_DOMAIN" ]]; then
  if tailscale ping --timeout=3s -c 1 "$ARCHITECT_DOMAIN" &>/dev/null; then
    result_pass "Architect (${ARCHITECT_DOMAIN}) — reachable via Tailscale"
  else
    result_fail "Architect (${ARCHITECT_DOMAIN}) — not reachable (check tailscale status)"
  fi
else
  result_fail "ARCHITECT_TS_DOMAIN not set — cannot test Architect reachability"
fi

# ---------------------------------------------------------------------------
# Test 2: Architect gateway responding (via Tailscale HTTPS)
# ---------------------------------------------------------------------------
print_header "Test 2: Architect Gateway — HTTPS Health Check"

if [[ -n "$ARCHITECT_DOMAIN" ]]; then
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${ARCHITECT_DOMAIN}:${PORT}/health" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    result_pass "Architect gateway (${ARCHITECT_DOMAIN}:${PORT}) — HTTPS 200"
  elif [[ "$code" == "000" ]]; then
    result_fail "Architect gateway (${ARCHITECT_DOMAIN}:${PORT}) — connection refused (check tailscale serve status on VM-1)"
  else
    result_warn "Architect gateway (${ARCHITECT_DOMAIN}:${PORT}) — HTTPS ${code}"
  fi
else
  result_fail "ARCHITECT_TS_DOMAIN not set — cannot test Architect gateway"
fi

# ---------------------------------------------------------------------------
# Test 3: Own gateway responding (loopback)
# ---------------------------------------------------------------------------
print_header "Test 3: Local Gateway — HTTP Health Check"

code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:${PORT}/health" 2>/dev/null || echo "000")
if [[ "$code" == "200" ]]; then
  result_pass "Local gateway (127.0.0.1:${PORT}) — HTTP 200"
elif [[ "$code" == "000" ]]; then
  result_fail "Local gateway (127.0.0.1:${PORT}) — not responding (check: openclaw daemon status)"
else
  result_warn "Local gateway (127.0.0.1:${PORT}) — HTTP ${code}"
fi

# Also verify Tailscale Serve is forwarding to this VM
MY_TS_DOMAIN="${GATEFORGE_VM_HOST:-}"
if [[ -n "$MY_TS_DOMAIN" ]]; then
  code_ts=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${MY_TS_DOMAIN}:${PORT}/health" 2>/dev/null || echo "000")
  if [[ "$code_ts" == "200" ]]; then
    result_pass "Tailscale Serve (${MY_TS_DOMAIN}:${PORT}) — HTTPS 200"
  elif [[ "$code_ts" == "000" ]]; then
    result_warn "Tailscale Serve (${MY_TS_DOMAIN}:${PORT}) — not responding (run: sudo tailscale serve --bg --https=${PORT} http://127.0.0.1:${PORT})"
  else
    result_warn "Tailscale Serve (${MY_TS_DOMAIN}:${PORT}) — HTTPS ${code_ts}"
  fi
fi

# ---------------------------------------------------------------------------
# Test 4: HMAC Notification → Architect (via Tailscale HTTPS)
# ---------------------------------------------------------------------------
print_header "Test 4: HMAC Notification → Architect"

# NOTIFY_URL should already be HTTPS (e.g. https://tonic-architect.sailfish-bass.ts.net:18789/hooks/agent)
# Fallback: construct from domain if NOTIFY_URL not set
EFFECTIVE_NOTIFY_URL="${NOTIFY_URL:-https://${ARCHITECT_DOMAIN}:${PORT}/hooks/agent}"
echo -e "  ${DIM}Target: ${EFFECTIVE_NOTIFY_URL}${RESET}"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PAYLOAD='{"name":"agent-notify","agentId":"architect","message":"[INFO] Connectivity test from '${ROLE}'","metadata":{"sourceVm":"'${ROLE}'","sourceRole":"'${ROLE}'","priority":"INFO","taskId":"SPOKE-TEST","timestamp":"'${TIMESTAMP}'"}}'
SIGNATURE=$(echo -n "${PAYLOAD}" | openssl dgst -sha256 -hmac "${SECRET}" | awk '{print $2}')

RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 5 \
  -X POST "${EFFECTIVE_NOTIFY_URL}" \
  -H "Authorization: Bearer ${HOOK_TOKEN}" \
  -H "X-Agent-Signature: ${SIGNATURE}" \
  -H "X-Source-VM: ${ROLE}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" 2>/dev/null || echo -e "\n000")

BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "202" ]]; then
  result_pass "HMAC notification accepted — HTTPS ${HTTP_CODE}"
elif [[ "$HTTP_CODE" == "401" ]]; then
  result_fail "HMAC notification rejected — HTTPS 401 (hook token wrong)"
elif [[ "$HTTP_CODE" == "403" ]]; then
  result_fail "HMAC notification rejected — HTTPS 403 (forbidden)"
elif [[ "$HTTP_CODE" == "404" ]]; then
  result_fail "HMAC notification — HTTPS 404 (webhooks not enabled on Architect VM)"
  echo -e "  ${DIM}Fix: On VM-1, add to ~/.openclaw/openclaw.json:${RESET}"
  echo -e "  ${DIM}  { \"hooks\": { \"enabled\": true, \"token\": \"<HOOK_TOKEN>\", \"path\": \"/hooks\" } }${RESET}"
  echo -e "  ${DIM}Then restart: openclaw daemon restart${RESET}"
elif [[ "$HTTP_CODE" == "000" ]]; then
  result_fail "HMAC notification — connection failed (check tailscale serve status on VM-1)"
else
  result_warn "HMAC notification — HTTPS ${HTTP_CODE}"
  if [[ -n "$BODY" ]]; then
    echo -e "  ${DIM}Response: ${BODY}${RESET}"
  fi
fi

# ---------------------------------------------------------------------------
# Test 5: Wrong hook token (should be rejected)
# ---------------------------------------------------------------------------
print_header "Test 5: Security — Wrong Hook Token (should fail)"

code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
  -X POST "${EFFECTIVE_NOTIFY_URL}" \
  -H "Authorization: Bearer wrong_token_12345" \
  -H "X-Agent-Signature: ${SIGNATURE}" \
  -H "X-Source-VM: ${ROLE}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" 2>/dev/null || echo "000")

if [[ "$code" == "401" || "$code" == "403" ]]; then
  result_pass "Wrong hook token correctly rejected — HTTPS ${code}"
elif [[ "$code" == "200" || "$code" == "202" ]]; then
  result_warn "Wrong hook token was ACCEPTED — HTTPS ${code} (Architect may not validate hook tokens)"
elif [[ "$code" == "404" ]]; then
  result_fail "HTTPS 404 — hook endpoint not found (fix Test 4 first — same root cause)"
else
  result_warn "Unexpected response — HTTPS ${code}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_header "Test Summary — ${ROLE}"

TOTAL=$((PASS + FAIL + WARN))
echo ""
echo -e "  ${GREEN}${BOLD}Passed:${RESET}   ${PASS}/${TOTAL}"
echo -e "  ${RED}${BOLD}Failed:${RESET}   ${FAIL}/${TOTAL}"
echo -e "  ${YELLOW}${BOLD}Warnings:${RESET} ${WARN}/${TOTAL}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "  ${GREEN}${BOLD}║  ALL TESTS PASSED — ${ROLE} communication OK              ║${RESET}"
  echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
else
  echo -e "  ${RED}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "  ${RED}${BOLD}║  FAILURES DETECTED — check details above                 ║${RESET}"
  echo -e "  ${RED}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
fi

echo ""
echo -e "  ${DIM}Troubleshooting:${RESET}"
echo -e "  ${DIM}  Tailscale:  tailscale ping tonic-architect.sailfish-bass.ts.net${RESET}"
echo -e "  ${DIM}  Serve:      tailscale serve status${RESET}"
echo -e "  ${DIM}  Port:       ss -tlnp | grep 18789${RESET}"
echo -e "  ${DIM}  Config:     sudo cat /opt/secrets/gateforge.env${RESET}"
echo -e "  ${DIM}  Logs:       journalctl -u openclaw-gateforge -n 20${RESET}"
echo ""

exit $FAIL
