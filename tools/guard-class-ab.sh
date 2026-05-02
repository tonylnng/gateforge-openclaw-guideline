#!/usr/bin/env bash
# guard-class-ab.sh
#
# Pre-commit guard for GateForge project (Blueprint) repos.
#
# Purpose: prevent the agent (or a human) from smuggling Class A or
# Class B content into a project repo. Class A (OpenClaw runtime
# contract) and Class B (methodology) files belong only in the
# central guideline repo. Project content must live in:
#   project/gateforge_<project_name>.md          (Class C)
#
# Install in a project repo:
#   cp tools/guard-class-ab.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Or wire into pre-commit-framework via .pre-commit-config.yaml.
#
# Exit codes:
#   0  no Class A / B violations
#   1  Class A or Class B file modified — commit blocked
#   2  invalid project file name detected

set -euo pipefail

# Patterns that identify Class A and Class B files (relative to repo root).
# These match the file *names* — projects rarely have these as legitimate
# top-level files; if they do, that is itself a Class A/B violation.
CLASS_A_PATTERNS='^(SOUL|AGENTS|USER|TOOLS)\.md$|^.*/openclaw\.json$|^install/.*\.sh$'
CLASS_B_PATTERNS='^(BLUEPRINT-GUIDE|DEVELOPMENT-GUIDE|QA-FRAMEWORK|QC-GUIDE|PM-GUIDE|SYSTEM-DESIGN-GUIDE|RESILIENCE-SECURITY-GUIDE|MONITORING-OPERATIONS-GUIDE|MULTI-AGENT-ADAPTATION|SINGLE-AGENT-ADAPTATION)\.md$|^roles/.*\.md$|^guideline/'

# Class C file-name regex: gateforge_<snake_case>.md
CLASS_C_PATTERN='^project/gateforge_[a-z][a-z0-9_]{2,40}\.md$'
CLASS_C_LIKE='^project/gateforge_'

# Get staged files (added, copied, modified, renamed).
STAGED=$(git diff --cached --name-only --diff-filter=ACMR)

if [ -z "$STAGED" ]; then
  exit 0
fi

violations=0

while IFS= read -r f; do
  [ -z "$f" ] && continue

  # Class A check
  if echo "$f" | grep -qE "$CLASS_A_PATTERNS"; then
    echo "ERROR: Class A file modified: $f" >&2
    echo "  Class A files (SOUL/AGENTS/USER/TOOLS, openclaw.json, install/*.sh) belong" >&2
    echo "  in the central guideline repo, not in a project repo." >&2
    echo "  Capture project-specific overrides in project/gateforge_<project_name>.md." >&2
    violations=$((violations + 1))
  fi

  # Class B check
  if echo "$f" | grep -qE "$CLASS_B_PATTERNS"; then
    echo "ERROR: Class B file modified: $f" >&2
    echo "  Class B files (BLUEPRINT-GUIDE, role guides, adaptation files) belong" >&2
    echo "  in the central guideline repo, not in a project repo." >&2
    echo "  Capture project-specific overrides in project/gateforge_<project_name>.md." >&2
    violations=$((violations + 1))
  fi

  # Class C name validation: any file under project/gateforge_* must match the regex.
  if echo "$f" | grep -qE "$CLASS_C_LIKE" && ! echo "$f" | grep -qE "$CLASS_C_PATTERN"; then
    echo "ERROR: Invalid Class C file name: $f" >&2
    echo "  Class C files must match: project/gateforge_<snake_case_name>.md" >&2
    echo "  Where <snake_case_name> matches: ^[a-z][a-z0-9_]{2,40}\$" >&2
    exit 2
  fi
done <<< "$STAGED"

if [ "$violations" -gt 0 ]; then
  echo "" >&2
  echo "$violations Class A/B violation(s). Commit blocked." >&2
  echo "If you are upgrading the guideline pin, do it as an Ops-phase commit on" >&2
  echo "project/state.md (guideline_commit:) only — do not copy guideline files in." >&2
  exit 1
fi

exit 0
