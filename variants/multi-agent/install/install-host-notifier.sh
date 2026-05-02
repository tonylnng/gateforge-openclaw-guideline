#!/usr/bin/env bash
# =============================================================================
# install-host-notifier.sh
# -----------------------------------------------------------------------------
# Installs the GateForge host-side notifier on a spoke VM (VM-2..VM-5).
# Invoked from setup-vmN-*.sh after /opt/secrets/gateforge.env has been
# written. Idempotent.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOST_DIR="${SCRIPT_DIR}/host-side"

command -v jq >/dev/null     || { echo "Installing jq..."; apt-get update -qq && apt-get install -y -qq jq; }
command -v openssl >/dev/null || { echo "openssl missing — aborting"; exit 1; }
command -v curl >/dev/null    || { echo "Installing curl..."; apt-get install -y -qq curl; }

install -d -m 0750 -o root -g root /opt/gateforge/bin
install -d -m 0755 -o root -g root /var/lib/gateforge

install -m 0750 -o root -g root "${HOST_DIR}/gf-notify-architect.sh"  /opt/gateforge/bin/gf-notify-architect.sh
install -m 0750 -o root -g root "${HOST_DIR}/gf-replay-deadletter.sh" /opt/gateforge/bin/gf-replay-deadletter.sh

install -m 0644 -o root -g root "${HOST_DIR}/gf-notify-architect.path"    /etc/systemd/system/gf-notify-architect.path
install -m 0644 -o root -g root "${HOST_DIR}/gf-notify-architect.service" /etc/systemd/system/gf-notify-architect.service

systemctl daemon-reload
systemctl enable --now gf-notify-architect.path

echo "gf-notify-architect installed and active."
echo ""
echo "Note: the systemd path unit watches /opt/gateforge/blueprint/.git/refs."
echo "It will fire only after the Blueprint repo is cloned to that path — do this"
echo "when starting a new project, not as part of OpenClaw setup."
echo ""
echo "Smoke test (run after cloning the Blueprint):"
echo "  cd /opt/gateforge/blueprint"
echo "  git checkout -b design/TASK-SMOKE-001"
echo "  echo '# smoke' > smoke.md && git add smoke.md"
echo '  git commit -m "docs: TASK-SMOKE-001 — smoke'
echo ''
echo '  GateForge-Task-Id: TASK-SMOKE-001'
echo '  GateForge-Priority: INFO'
echo "  GateForge-Source-VM: vm-\${GATEFORGE_VM_NUM}"
echo "  GateForge-Source-Role: \${GATEFORGE_ROLE}"
echo '  GateForge-Summary: Host-side notifier smoke test"'
echo "  git push origin design/TASK-SMOKE-001"
echo "  journalctl -t gf-notify-architect -n 20"
