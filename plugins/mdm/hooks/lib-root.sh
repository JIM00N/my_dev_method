#!/usr/bin/env bash
# 훅 공용 — 제품 루트와 키트 표식을 찾는다. 세 훅이 source 로 읽는다 (단독 실행하지 않는다).
#
# 출발점: MDM_PROJECT_ROOT → CLAUDE_PROJECT_DIR → PWD — 엔진(plugins/mdm/scripts/mdm_env.py)과 같은 우선순위다.
# 표식(docs/status/STATUS.md)이 출발점에 없으면 **그 git 저장소의 최상위까지** 위로 올라가며 찾는다.
# 하위 디렉토리에서 띄운 세션은 CLAUDE_PROJECT_DIR 가 그 하위 경로다 (2026-09-11 `claude -p` 실측, issues #426) —
# 출발점만 보면 사용자 범위로 설치한 플러그인의 훅이 그 세션에서 조용히 판정을 건너뛴다.
# git 밖이면 출발점만 본다 — 저장소 경계 없이 위로 가면 남의 디렉토리의 표식을 줍는다.
#
# 찾으면 ROOT 를 그 디렉토리로 두고 0, 못 찾으면 1 — 호출자는 1 이면 판정하지 않고 통과한다
# (플러그인 훅은 켜진 모든 저장소에서 돌기 때문이다. 플러그인 README 「훅이 판정하는 저장소」).
mdm_find_root() {
  local start top d
  start="${MDM_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  [ -d "$start" ] || return 1
  start="$(cd "$start" && pwd)" || return 1
  if [ -f "$start/docs/status/STATUS.md" ]; then ROOT="$start"; return 0; fi
  top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] || return 1
  top="$(cd "$top" && pwd -P)" || return 1
  d="$start"
  while [ "$(cd "$d" && pwd -P)" != "$top" ] && [ "$d" != "/" ]; do
    d="$(dirname "$d")"
    if [ -f "$d/docs/status/STATUS.md" ]; then ROOT="$d"; return 0; fi
  done
  return 1
}
