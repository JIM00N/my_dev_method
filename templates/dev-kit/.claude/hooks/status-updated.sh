#!/usr/bin/env bash
# Stop 훅 — 작업 트리에 변경이 있는데 STATUS.md를 갱신하지 않고 세션을 끝내는 것을 막는다.
# CLAUDE.md 절대 규칙 9의 기계적 강제판.
# 실패 시에는 항상 통과(exit 0)시킨다. 훅이 작업을 막는 원인이 되면 안 된다.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STATUS="$ROOT/docs/status/STATUS.md"
input=$(cat 2>/dev/null || true)

# 이 훅 때문에 이미 한 번 막혔으면 통과시킨다 (무한 루프 방지)
if command -v jq >/dev/null 2>&1; then
  active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
  [ "$active" = "true" ] && exit 0
fi

[ -f "$STATUS" ] || exit 0                                   # 키트 미적용 저장소
command -v git >/dev/null 2>&1 || exit 0
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 작업이 실제로 있었을 때만 요구한다. 변경이 없으면 갱신할 것도 없다.
[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] || exit 0

today=$(date +%F)
line=$(grep -m1 '최종 갱신' "$STATUS" 2>/dev/null || true)
case "$line" in
  *"$today"*) exit 0 ;;
esac

cat >&2 <<MSG
STATUS 미갱신 — 세션을 끝낼 수 없다 (CLAUDE.md 절대 규칙 9).

작업 트리에 변경이 있는데 docs/status/STATUS.md의 "최종 갱신"이 오늘(${today})이 아니다.
다음 세션이 맥락 없이 시작하는 것을 막기 위한 장치다.

지금 갱신할 것:
  - 최종 갱신(오늘 날짜·시각) / 현재 단계 / 현재 사이클
  - "지금 하고 있는 일" 한 문장
  - "다음 3가지"
  - 열린 이슈·막힌 것 (해결·검증된 것은 archive로 옮기고 STATUS에서는 제거)

갱신한 뒤 다시 종료하라.
MSG
exit 2
