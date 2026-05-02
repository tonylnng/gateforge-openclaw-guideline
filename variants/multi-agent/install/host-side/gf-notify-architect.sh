#!/usr/bin/env bash
# =============================================================================
# gf-notify-architect.sh
# -----------------------------------------------------------------------------
# Host-side HMAC-signed callback dispatcher for GateForge spoke VMs.
# Triggered by systemd path unit on changes to the Blueprint Git refs.
# Reads GateForge-* trailers from the latest commit on each updated branch,
# signs the payload with AGENT_SECRET, and POSTs to the Architect's
# /hooks/agent endpoint.
# -----------------------------------------------------------------------------
# Location: /opt/gateforge/bin/gf-notify-architect.sh
# Owner:    root:root   Mode: 0750
# Runs as:  root (via systemd oneshot service)
# =============================================================================
set -euo pipefail

SECRETS=/opt/secrets/gateforge.env
LOG_TAG=gf-notify-architect
BLUEPRINT_REPO=${BLUEPRINT_REPO:-/opt/gateforge/blueprint}
STATE_DIR=/var/lib/gateforge
mkdir -p "$STATE_DIR"

# shellcheck disable=SC1090
source "$SECRETS"

: "${AGENT_SECRET:?missing in $SECRETS}"
: "${ARCHITECT_HOOK_TOKEN:?missing in $SECRETS}"
: "${ARCHITECT_NOTIFY_URL:?missing in $SECRETS}"
: "${GATEFORGE_ROLE:?missing in $SECRETS}"       # designer|developers|qc-agents|operator
: "${GATEFORGE_VM_NUM:?missing in $SECRETS}"     # 2|3|4|5

cd "$BLUEPRINT_REPO"

LAST_SEEN="$STATE_DIR/last-seen-refs"
[ -f "$LAST_SEEN" ] || : > "$LAST_SEEN"

CURRENT_REFS=$(git for-each-ref --format='%(refname:short) %(objectname)' refs/heads/)

echo "$CURRENT_REFS" | while read -r branch sha; do
  [ -n "$branch" ] || continue
  prev=$(grep "^$branch " "$LAST_SEEN" 2>/dev/null | awk '{print $2}' || true)
  if [ "$prev" = "$sha" ]; then
    continue
  fi

  # Only notify on GateForge task branches
  case "$branch" in
    design/TASK-*|feature/TASK-*|test/TASK-*|deploy/TASK-*|hotfix/BUG-*) : ;;
    *) continue ;;
  esac

  MSG=$(git log -1 --pretty=%B "$sha")
  TASK_ID=$(printf '%s\n' "$MSG"     | awk -F': ' '/^GateForge-Task-Id:/     {print $2; exit}')
  PRIORITY=$(printf '%s\n' "$MSG"    | awk -F': ' '/^GateForge-Priority:/    {print $2; exit}')
  SUMMARY=$(printf '%s\n' "$MSG"     | awk -F': ' '/^GateForge-Summary:/     {print $2; exit}')
  SOURCE_ROLE=$(printf '%s\n' "$MSG" | awk -F': ' '/^GateForge-Source-Role:/ {print $2; exit}')

  if [ -z "${TASK_ID:-}" ] || [ -z "${PRIORITY:-}" ]; then
    logger -t "$LOG_TAG" "Malformed commit $sha on $branch — missing trailers, sending BLOCKED"
    PRIORITY=BLOCKED
    TASK_ID="MALFORMED-$(printf '%s' "$sha" | cut -c1-7)"
    SUMMARY="Commit $sha on $branch missing GateForge-* trailers. Agent non-compliance — investigate."
    SOURCE_ROLE="$GATEFORGE_ROLE"
  fi

  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  PAYLOAD=$(jq -cn \
    --arg agentId  "architect" \
    --arg name     "agent-notify" \
    --arg msg      "[${PRIORITY}] ${TASK_ID} — ${SUMMARY:-no summary provided}" \
    --arg vm       "vm-${GATEFORGE_VM_NUM}" \
    --arg role     "${SOURCE_ROLE:-$GATEFORGE_ROLE}" \
    --arg prio     "$PRIORITY" \
    --arg task     "$TASK_ID" \
    --arg ts       "$TS" \
    --arg branch   "$branch" \
    --arg sha      "$sha" \
    '{name:$name, agentId:$agentId, message:$msg,
      metadata:{sourceVm:$vm, sourceRole:$role, priority:$prio,
                taskId:$task, timestamp:$ts, branch:$branch, commit:$sha}}')

  SIGNATURE=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$AGENT_SECRET" | awk '{print $2}')

  HTTP=$(curl -sS -o /tmp/gf-notify.out -w '%{http_code}' \
    -X POST "$ARCHITECT_NOTIFY_URL" \
    -H "Authorization: Bearer ${ARCHITECT_HOOK_TOKEN}" \
    -H "X-Agent-Signature: ${SIGNATURE}" \
    -H "X-Source-VM: vm-${GATEFORGE_VM_NUM}" \
    -H "Content-Type: application/json" \
    --max-time 10 \
    --retry 3 --retry-delay 2 --retry-connrefused \
    -d "$PAYLOAD" || echo "000")

  if [ "$HTTP" = "200" ]; then
    logger -t "$LOG_TAG" "OK  $branch $sha $PRIORITY $TASK_ID"
  else
    body=$(head -c 200 /tmp/gf-notify.out 2>/dev/null || true)
    logger -t "$LOG_TAG" "ERR $branch $sha http=$HTTP body=${body}"
    echo "$TS $branch $sha $HTTP $TASK_ID $PRIORITY" >> "$STATE_DIR/dead-letter.log"
  fi
done

# Atomically update the seen-refs snapshot (only after successful walk)
printf '%s\n' "$CURRENT_REFS" > "$LAST_SEEN.tmp" && mv "$LAST_SEEN.tmp" "$LAST_SEEN"
