#!/usr/bin/env bash
# =============================================================================
# gf-replay-deadletter.sh
# -----------------------------------------------------------------------------
# Replays entries from /var/lib/gateforge/dead-letter.log by re-triggering
# gf-notify-architect for the branches listed. Useful after an Architect
# outage. Idempotent — the Architect should dedupe on commit SHA.
# -----------------------------------------------------------------------------
# Run manually: sudo /opt/gateforge/bin/gf-replay-deadletter.sh
# =============================================================================
set -euo pipefail

DL=/var/lib/gateforge/dead-letter.log
LAST_SEEN=/var/lib/gateforge/last-seen-refs

[ -f "$DL" ] || { echo "No dead-letter entries."; exit 0; }

# Reset last-seen for affected branches so the next notifier run re-dispatches.
awk '{print $2}' "$DL" | sort -u | while read -r branch; do
  grep -v "^$branch " "$LAST_SEEN" > "$LAST_SEEN.tmp" || true
  mv "$LAST_SEEN.tmp" "$LAST_SEEN"
  echo "Reset last-seen for $branch"
done

# Archive current dead-letter and trigger notifier
mv "$DL" "$DL.$(date -u +%Y%m%dT%H%M%SZ)"
systemctl start gf-notify-architect.service
echo "Replay triggered. Check: journalctl -t gf-notify-architect -n 50"
