#!/usr/bin/env bash
# Stop 훅 — 작업 트리에 변경이 있는데 STATUS.md를 갱신하지 않고 세션을 끝내는 것을 막는다.
# CLAUDE.md 절대 규칙 9의 기계적 강제판.
# 실패 시에는 항상 통과(exit 0)시킨다. 훅이 작업을 막는 원인이 되면 안 된다.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STATUS="$ROOT/docs/status/STATUS.md"
input=$(cat 2>/dev/null || true)

# 루프 방지 1: Claude Code가 주는 신호
if command -v jq >/dev/null 2>&1; then
  active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
  [ "$active" = "true" ] && exit 0
fi

# 루프 방지 2: 파일 기반 차단기 — 같은 프로젝트에서 30분 안에 두 번째 차단은 하지 않는다.
# (jq가 없거나 신호가 오지 않아도 에이전트가 만족 불가능한 조건에 갇히지 않게 한다)
marker="${TMPDIR:-/tmp}/claude-status-guard-$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
if [ -f "$marker" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0) ))
  rm -f "$marker"
  [ "$age" -lt 1800 ] && exit 0
fi

[ -f "$STATUS" ] || exit 0                                   # 키트 미적용 저장소
command -v git >/dev/null 2>&1 || exit 0
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 작업이 실제로 있었을 때만 요구한다. 변경이 없으면 갱신할 것도 없다.
[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] || exit 0

# "최종 갱신" 필드 행을 찾는다 (굵은 필드 우선, 없으면 첫 일치)
line=$(grep -m1 -E '^\*\*최종 갱신\*\*' "$STATUS" 2>/dev/null || true)
[ -n "$line" ] || line=$(grep -m1 '최종 갱신' "$STATUS" 2>/dev/null || true)

# 오늘 날짜를 흔한 표기 전부로 인정한다: 2026-08-26 / 2026.08.26 / 2026. 08. 26. / 2026/08/26 /
# 2026년 8월 26일 (월·일의 앞자리 0 유무 무관)
Y=$(date +%Y); M=$(date +%m); D=$(date +%d); m=${M#0}; d=${D#0}
if printf '%s' "$line" | grep -Eq \
  "${Y}[-./년][[:space:]]?0?${m}[-./월][[:space:]]?0?${d}(일)?\.?"; then
  rm -f "$marker" 2>/dev/null
  exit 0
fi

touch "$marker" 2>/dev/null || true
cat >&2 <<MSG
STATUS 미갱신 — 세션을 끝낼 수 없다 (CLAUDE.md 절대 규칙 9).

작업 트리에 변경이 있는데 docs/status/STATUS.md의 "최종 갱신"이 오늘($(date +%F))이 아니다.
다음 세션이 맥락 없이 시작하는 것을 막기 위한 장치다.

지금 갱신할 것:
  - 최종 갱신(오늘 날짜·시각) / 현재 단계 / 현재 사이클
  - "지금 하고 있는 일" 한 문장
  - "다음 3가지"
  - 열린 이슈·막힌 것 (해결·검증된 것은 archive로 옮기고 STATUS에서는 제거)

갱신한 뒤 다시 종료하라. (이 훅은 같은 세션에서 두 번 연속 막지 않는다)
MSG
exit 2
