#!/usr/bin/env bash
# Final integration check, independent of the editor or coding agent.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$ROOT/.claude/scripts/check-consistency.sh"
python3 "$ROOT/.claude/scripts/mdm-ops.py" handoff-check
