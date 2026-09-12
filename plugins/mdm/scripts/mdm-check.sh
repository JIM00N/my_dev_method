#!/usr/bin/env bash
# 최종 통합 검사 — 편집기·코딩 에이전트와 무관하게 돈다 (`mdm final`). 종료·CI 용.
#   1) 정합성 검사 A~K (check-consistency.sh)   2) 현재 파일 집합에 대응하는 인계 기록 (mdm-ops.py handoff-check)
#
# 제품 루트는 MDM_PROJECT_ROOT → CLAUDE_PROJECT_DIR → git 루트 → 현재 디렉토리 순으로 정한다
# (plugins/mdm/scripts/mdm_env.py 머리말이 정본). 엔진은 플러그인 안에 있어 자기 경로로는 제품을 못 찾는다.
set -euo pipefail
ENGINE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${MDM_PROJECT_ROOT:-}" ]; then ROOT="$MDM_PROJECT_ROOT"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then ROOT="$CLAUDE_PROJECT_DIR"
else ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; fi
ROOT="$(cd "$ROOT" && pwd)"
export MDM_PROJECT_ROOT="$ROOT"
echo "최종 통합 검사 — 제품: $ROOT"
bash "$ENGINE/check-consistency.sh"
python3 "$ENGINE/mdm-ops.py" handoff-check
