#!/usr/bin/env bash
# PreToolUse(Bash) 훅 — docs/spec/stack.md에 없는 패키지 설치를 막는다.
# CLAUDE.md 절대 규칙 4의 기계적 강제판.
# 판단이 불확실하면 통과시킨다. 오탐으로 작업을 막는 것보다 낫다.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STACK="$ROOT/docs/spec/stack.md"
input=$(cat 2>/dev/null || true)

command -v jq >/dev/null 2>&1 || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -n "$cmd" ] || exit 0

# 이름에서 버전 지정을 떼어낸다: pkg@1.2 / pkg==1.2 / pkg>=1 / @scope/pkg@1
strip_version() {
  local t="$1"
  case "$t" in
    @*) printf '%s' "$(printf '%s' "$t" | sed -E 's#^(@[^/]+/[^@]+).*$#\1#')" ;;
    *)  printf '%s' "$(printf '%s' "$t" | sed -E 's/[@=<>!~[].*$//')" ;;
  esac
}

pkgs=""
while IFS= read -r seg || [ -n "$seg" ]; do
  [ -n "$seg" ] || continue
  # shellcheck disable=SC2086
  set -- $seg
  [ $# -ge 2 ] || continue
  mgr="$(basename "$1")"; sub="$2"; take=0
  case "$mgr:$sub" in
    npm:install|npm:i|npm:add|pnpm:install|pnpm:i|pnpm:add|yarn:add|bun:add|bun:install) take=1 ;;
    pip:install|pip3:install|uv:add|poetry:add|cargo:add|gem:install|composer:require) take=1 ;;
    go:get) take=1 ;;
    *) take=0 ;;
  esac
  [ "$take" = 1 ] || continue
  shift 2
  for tok in "$@"; do
    case "$tok" in
      -*|.|./*|/*|../*|'$'*|'`'*) continue ;;       # 플래그·로컬 경로·치환은 대상 아님
      python|-m) continue ;;
    esac
    name="$(strip_version "$tok")"
    [ -n "$name" ] && pkgs="$pkgs $name"
  done
done < <(printf '%s\n' "$cmd" | tr ';|&\n' '\n\n\n\n')

# 인자 없는 npm install / pnpm i 등은 lockfile 복원이므로 통과
pkgs="$(printf '%s' "$pkgs" | tr ' ' '\n' | grep -v '^$' | sort -u || true)"
[ -n "$pkgs" ] || exit 0

if [ ! -f "$STACK" ]; then
  cat >&2 <<MSG
docs/spec/stack.md가 없다. 기술 스택을 확정하기 전에 패키지를 설치하지 않는다.
docs/guides/S4-architecture.md 2부를 먼저 수행하라.
설치하려던 것: $(printf '%s' "$pkgs" | tr '\n' ' ')
MSG
  exit 2
fi

missing=""
while IFS= read -r p || [ -n "$p" ]; do
  [ -n "$p" ] || continue
  grep -qiF -- "$p" "$STACK" || missing="$missing $p"
done <<< "$pkgs"

[ -n "$(printf '%s' "$missing" | tr -d ' ')" ] || exit 0

cat >&2 <<MSG
stack.md에 없는 기술 도입 시도 — 차단 (CLAUDE.md 절대 규칙 4).

docs/spec/stack.md에서 찾을 수 없는 항목:$missing

임의로 고르지 않는다. 먼저 사용자에게
  ① 어떤 기술 영역인가 ② 장점 ③ 단점·종속성 ④ 검토한 대체제와 추천 이유
를 제시하고 승인을 받은 뒤, docs/spec/stack.md의 결정 표에 [영역 · 선택 · 탈락 대체제 · 선택 이유]로 추가하라.
되돌리기 어려운 선택이면 docs/decisions/에 ADR도 남긴다.
MSG
exit 2
