#!/usr/bin/env bash
# 리뷰 통과 도장 — /kit-review 통과 시 --write 로 "커밋될 트리"의 git object id 를 찍고,
# .githooks/pre-commit 이 커밋 시점에 --verify 로 실제 커밋 트리를 그 도장과 대조한다.
#
# 지문은 git write-tree 로 낸다 — git 이 트리를 계산하므로 파일명 인용·비ASCII·
# 인덱스/작업트리 차이·개행에 흔들리지 않는다. git 이 실패하면 삼키지 않고 비-0 으로 낸다(fail-closed).
#
# 신뢰 경계(정직하게): 이 장치가 기계적으로 보장하는 것은 "커밋되는 트리 == 도장 찍힌 트리"까지다.
# 도장은 /kit-review 흐름이 찍는다. **리뷰가 실제로 돌았음을 암호학적으로 증명하지는 못한다** —
# 그 연결(도장 ⇒ 리뷰)은 기계가 아니라 절차(에이전트 신뢰)다. 이 저장소에 그 이상의 신뢰 뿌리는 없다.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MARK="$ROOT/.claude/.kit-review-pass"

# 커밋될 전체 트리(모든 변경을 add 했을 때)의 object id. 실제 인덱스를 건드리지 않도록 임시 인덱스로 계산한다.
prospective_tree() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local tmpidx rc tree
  tmpidx="$(mktemp)" || return 1
  rm -f "$tmpidx"   # git read-tree 가 새로 만든다 — 빈 파일은 유효 인덱스가 아니다
  rc=0
  if git -C "$ROOT" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    GIT_INDEX_FILE="$tmpidx" git -C "$ROOT" read-tree HEAD || rc=1
  else
    GIT_INDEX_FILE="$tmpidx" git -C "$ROOT" read-tree --empty || rc=1
  fi
  [ "$rc" = 0 ] && { GIT_INDEX_FILE="$tmpidx" git -C "$ROOT" add -A || rc=1; }
  tree=""
  [ "$rc" = 0 ] && { tree="$(GIT_INDEX_FILE="$tmpidx" git -C "$ROOT" write-tree)" || rc=1; }
  rm -f "$tmpidx"
  [ "$rc" = 0 ] && [ -n "$tree" ] || return 1
  printf '%s\n' "$tree"
}

# 지금 커밋하면 실제로 만들어질 트리(현재 인덱스). pre-commit 이 이걸 도장과 대조한다.
committed_tree() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "$ROOT" write-tree
}

case "${1:-}" in
  --write)
    t="$(prospective_tree)" || { echo "리뷰 도장 실패: git 트리를 계산할 수 없다 (git 저장소가 아니거나 git 미설치)" >&2; exit 1; }
    printf '%s\n' "$t" > "$MARK" || exit 1
    echo "리뷰 도장 기록: ${MARK#"$ROOT"/} (트리 ${t:0:12})"
    ;;
  --verify)
    # pre-commit 용: 실제 커밋될 트리(인덱스)가 도장과 일치하는가. 어느 단계라도 실패하면 fail-closed.
    [ -f "$MARK" ] || exit 1
    stamp="$(cat "$MARK")" || exit 1
    [ -n "$stamp" ] || exit 1
    t="$(committed_tree)" || exit 1
    [ -n "$t" ] || exit 1
    [ "$t" = "$stamp" ] || exit 1
    ;;
  *)
    echo "사용법: review-stamp.sh --write | --verify" >&2
    exit 64
    ;;
esac
