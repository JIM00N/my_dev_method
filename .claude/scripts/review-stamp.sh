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

# 임시 인덱스는 **디렉토리 안**에 만든다 (mktemp -d 는 0700 으로 만들어진다).
# `mktemp` 로 파일을 만든 뒤 지우고 그 이름을 git 에 넘기면 그 틈에 남이 끼어들 수 있었다(TOCTOU).
#
# 트랩에 대해 (이슈 #100 — 여기서 두 번 틀렸다):
#  ① 트랩은 **이 함수 안**에 건다. `t="$(prospective_tree)"` 의 명령치환 **서브셸**에서 도는데,
#     바깥에 걸면 부모의 핸들러가 서브셸에서 대입된 값을 못 봐서 **아무것도 정리하지 않는다.**
#  ② 신호 목록은 **EXIT 하나뿐**이다. bash 3.2 는 EXIT 트랩만으로도 SIGINT/TERM/HUP 에서 돈다.
#     주의: 1회전은 `INT TERM HUP` 을 덧붙이면 "신호를 삼켜 계속 돈다"고 적었으나 **이 스크립트에서는
#     그 차이가 관측되지 않는다**(2회전 실측: 두 판본 모두 rc 130). 관용으로 EXIT 하나를 지키되,
#     회귀 검사가 재는 것은 **누수**뿐이다 — 없는 차이를 재는 케이스는 두지 않았다.

# 커밋될 전체 트리(모든 변경을 add 했을 때)의 object id. 실제 인덱스를 건드리지 않도록 임시 인덱스로 계산한다.
prospective_tree() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local tmpidx rc tree
  # `local` 로 두지 않는다 — 함수가 반환하면 지역 변수가 먼저 사라지고, 그 **뒤에** 서브셸의
  # EXIT 트랩이 돌아 `set -u` 로 죽는다. 트랩 쪽도 빈 값을 견디게 감싼다.
  # 접두어를 준다 — 공용 임시 디렉토리에서 **내 것을 남의 것과 구별**하기 위해서다.
  # 무템플릿 `mktemp -d` 는 `tmp.XXXX` 라 남의 것과 섞이고, 회귀 검사가 누수를 세려면
  # 공용 디렉토리를 통째로 스냅샷해야 해서 **남의 디렉토리를 지우는 사고**가 났다(2회전 K3·K6).
  # (macOS 의 bare `mktemp -d` 는 `TMPDIR` 도 따르지 않는다 — 템플릿을 줘야 따른다.)
  _stamp_tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/kit-stamp.XXXXXX")" || return 1
  trap '[ -n "${_stamp_tmpdir:-}" ] && rm -rf "$_stamp_tmpdir"' EXIT
  tmpidx="$_stamp_tmpdir/index"   # 아직 없는 경로 — git read-tree 가 새로 만든다
  rc=0
  if git -C "$ROOT" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    GIT_INDEX_FILE="$tmpidx" git -C "$ROOT" read-tree HEAD || rc=1
  else
    GIT_INDEX_FILE="$tmpidx" git -C "$ROOT" read-tree --empty || rc=1
  fi
  [ "$rc" = 0 ] && { GIT_INDEX_FILE="$tmpidx" git -C "$ROOT" add -A || rc=1; }
  tree=""
  [ "$rc" = 0 ] && { tree="$(GIT_INDEX_FILE="$tmpidx" git -C "$ROOT" write-tree)" || rc=1; }
  rm -rf "$_stamp_tmpdir"; _stamp_tmpdir=""
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
