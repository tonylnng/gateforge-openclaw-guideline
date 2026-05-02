#!/usr/bin/env bash
# bootstrap-project.sh
#
# Interactive helper that asks for a project name, validates it against
# the snake_case regex, and creates the project's Class C file from the
# template at templates/gateforge_PROJECT_TEMPLATE.md.
#
# Usage:
#   ./tools/bootstrap-project.sh                       # prompts for name
#   ./tools/bootstrap-project.sh acme_billing          # name as arg
#   ./tools/bootstrap-project.sh acme_billing /path    # name + Blueprint root
#
# The script writes the new file at:
#   <blueprint-root>/project/gateforge_<name>.md

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/templates/gateforge_PROJECT_TEMPLATE.md"

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found at $TEMPLATE" >&2
  exit 1
fi

# Argument 1: project name (optional)
NAME="${1:-}"
if [ -z "$NAME" ]; then
  read -rp "Project name (snake_case, lowercase, 3-40 chars): " NAME
fi

# Validate
if ! echo "$NAME" | grep -qE '^[a-z][a-z0-9_]{2,40}$'; then
  echo "ERROR: invalid project name: $NAME" >&2
  echo "  Must match: ^[a-z][a-z0-9_]{2,40}\$" >&2
  echo "  - lowercase letters, digits, and underscores only" >&2
  echo "  - first character must be a letter" >&2
  echo "  - 3 to 40 characters total" >&2
  exit 2
fi

# Argument 2: Blueprint repo root (optional)
BLUEPRINT_ROOT="${2:-$PWD}"
if [ ! -d "$BLUEPRINT_ROOT" ]; then
  echo "ERROR: Blueprint root not found: $BLUEPRINT_ROOT" >&2
  exit 3
fi

PROJECT_DIR="$BLUEPRINT_ROOT/project"
DEST="$PROJECT_DIR/gateforge_${NAME}.md"

if [ -e "$DEST" ]; then
  echo "ERROR: $DEST already exists. Refusing to overwrite." >&2
  exit 4
fi

mkdir -p "$PROJECT_DIR"

# Substitute project name into the template
TODAY="$(date +%Y-%m-%d)"
sed \
  -e "s/<project_name>/${NAME}/g" \
  -e "s/<YYYY-MM-DD>/${TODAY}/g" \
  "$TEMPLATE" > "$DEST"

echo "Created $DEST"
echo ""
echo "Next steps:"
echo "  1. Open $DEST and fill in the Metadata section."
echo "  2. In project/state.md, add: project_file: project/gateforge_${NAME}.md"
echo "  3. Commit with: [PM] Bootstrap project ${NAME}"
echo "     - GateForge-Phase: PM"
echo "     - GateForge-Iteration: 0"
echo "     - GateForge-Status: Bootstrap"
echo "     - GateForge-Summary: Project ${NAME} created from template"
