#!/usr/bin/env bash
# 리뷰 게이트 회귀 검사 — git pre-commit·pre-merge-commit 훅과 review-stamp.sh 도장을 임시 git 저장소에서 실측한다.
# "막는다"는 약속의 증거가 이 파일이다 (루트 CLAUDE.md 절대 규칙 3).
#
# 차단 판정에 teeth 를 준다(K6 3회전): "차단"을 HEAD 불변만으로 보지 않고 훅의 차단 신호(stderr)까지 요구한다 —
# 스테이징이 없어 "커밋할 것이 없다"로 실패한 것을 차단으로 오인하지 않는다. 끝에 뮤테이션 자기검증으로 이를 다시 못박는다.
#
# 봉쇄를 실증하는 우회(이전 회전에 뚫렸던 것): sh -c·$(...)·백틱·함수·줄이음(K2 2회전),
# 인덱스≠작업트리(K2 2회전), 비ASCII 파일명(K3 2회전), 부분·대체 인덱스 모드·병합(K2 3회전).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.githooks" "$TMP/.claude/scripts"
cp "$ROOT/.githooks/pre-commit" "$ROOT/.githooks/pre-merge-commit" "$TMP/.githooks/"
cp "$ROOT/.claude/scripts/review-stamp.sh" "$TMP/.claude/scripts/"
chmod +x "$TMP/.githooks/"* "$TMP/.claude/scripts/review-stamp.sh"
printf '/.claude/.kit-review-pass\n' > "$TMP/.gitignore"

cd "$TMP"
# 게이트는 **에이전트 셸에서만** 건다(사용자는 권한자). 이 fixture 는 에이전트 셸을 명시적으로 흉내 내
# 로컬·CI 어디서 돌든 같은 결과를 내게 한다 — 이 export 가 없으면 CI(에이전트 아님)에서 전부 통과해 검사가 무의미해진다.
export CLAUDECODE=1
git init -q .
git config user.email t@t.t
git config user.name t
git config core.hooksPath .githooks
DEF="$(git symbolic-ref --short HEAD)"   # 기본 브랜치명(main/master 무관)
printf 'v1\n' > app.txt
git add -A
git -c core.hooksPath=/dev/null commit -qm init   # 최초 커밋은 게이트 밖

STAMP=.claude/scripts/review-stamp.sh
SIG='커밋 차단'
fail=0

# 차단 기대: HEAD 불변 AND 훅 차단 신호가 있어야 진짜 차단. 신호 없이 HEAD만 불변이면 '빈 커밋 오인'으로 실패 처리.
expect_blocked() { # $1 설명  $2 커밋 셸 코드
  local h out; h="$(git rev-parse HEAD)"
  out="$(eval "$2" 2>&1)" || true
  if [ "$(git rev-parse HEAD)" != "$h" ]; then echo "실패[차단 기대]: $1 — 커밋이 생성됐다"; fail=1; return; fi
  case "$out" in
    *"$SIG"*) : ;;
    *) echo "실패[차단 기대]: $1 — HEAD는 불변이나 훅 차단 신호가 없다(빈 커밋 등 다른 이유일 수 있음)"; fail=1 ;;
  esac
}
expect_committed() { # $1 설명  $2 커밋 셸 코드
  local h out; h="$(git rev-parse HEAD)"
  out="$(eval "$2" 2>&1)" || true
  [ "$(git rev-parse HEAD)" != "$h" ] || { echo "실패[통과 기대]: $1 — 커밋이 막혔다 ($out)"; fail=1; }
}
uniq_stage() { printf '%s\n' "$1" >> app.txt; git add -A; }   # 고유 변경을 스테이징 — 각 케이스 독립

# 1) 도장 없이 평범한 커밋 — 에이전트 셸이면 차단
uniq_stage c1
expect_blocked "도장 없는 git commit(에이전트 셸)" 'git commit -m x'

# 1-b) 같은 상태에서 **사용자 셸**(에이전트 표식 없음)은 통과해야 한다 —
#      사용자는 리뷰 지적의 반영 여부를 정하는 권한자이지 통제 대상이 아니다.
expect_committed "사용자 셸은 도장 없이도 커밋 가능" 'env -u CLAUDECODE -u AI_AGENT git commit -m user-commit'

# 2) 셸 우회 표기 — git 네이티브라 전부 차단. 각 케이스마다 고유 변경을 스테이징(hollow 방지)
uniq_stage c2a; expect_blocked "sh -c 우회"      'sh -c "git commit -m x"'
uniq_stage c2b; expect_blocked "서브셸 (...)"     '(git commit -m x)'
uniq_stage c2c; expect_blocked "명령치환 \$(...)"  'y=$(git commit -m x)'
uniq_stage c2d; expect_blocked "백틱"             'y=`git commit -m x`'
uniq_stage c2e; expect_blocked "함수 우회"        'g(){ git "$@"; }; g commit -m x'
uniq_stage c2f; expect_blocked "줄이음"           'git \
commit -m x'

# 3) 부분·대체 인덱스 모드도 차단 (K2 3회전: git 이 실제 커밋 트리를 훅에 넘긴다)
uniq_stage c3; expect_blocked "pathspec 부분 커밋" 'git commit -m x app.txt'
expect_blocked "git commit -a"      'git commit -am x'
expect_blocked "git commit --amend" 'git commit --amend --no-edit'

# 4) 도장을 찍으면 그 트리는 통과
"$STAMP" --write
expect_committed "도장 후 커밋" 'git commit -m ok1'

# 5) 커밋 직후 새 변경 — 재차단
uniq_stage c5
expect_blocked "리뷰 이후 변경" 'git commit -m x'

# 6) 인덱스≠작업트리 공격(K2·K3 2회전): 작업트리는 도장과 동일, 인덱스만 미리뷰 → 게이트는 인덱스를 봐야 차단
git reset -q --hard HEAD
printf 'reviewed\n' > app.txt
"$STAMP" --write                       # 도장 = tree(app.txt=reviewed)
printf 'MALICIOUS\n' > app.txt; git add app.txt   # 인덱스 = tree(MALICIOUS)
printf 'reviewed\n' > app.txt          # 작업트리만 도장 상태로 되돌림(인덱스는 MALICIOUS 유지)
expect_blocked "인덱스 오염(작업트리는 도장과 동일)" 'git commit -m x'
git reset -q --hard HEAD

# 7) 비ASCII(한글) 파일명 내용 변경(K3 2회전) — 도장 후 한글 파일 내용을 바꾸면 재차단
printf 'k1\n' > 메모.txt
git add -A; "$STAMP" --write; git commit -qm add-memo
printf 'CHANGED\n' > 메모.txt; git add -A
expect_blocked "한글 파일명 내용 변경" 'git commit -m x'
git reset -q --hard HEAD

# 8) 도장 없는 non-ff 병합 — pre-merge-commit 이 차단(K2 3회전)
git checkout -q -b feat
printf 'feat\n' > feat.txt; git add -A; "$STAMP" --write; git commit -qm feat
git checkout -q "$DEF"
rm -f .claude/.kit-review-pass
expect_blocked "도장 없는 non-ff 병합(에이전트 셸)" 'git merge --no-ff --no-edit feat'
git merge --abort 2>/dev/null || true
# 8-b) 같은 병합을 **사용자 셸**로 하면 통과해야 한다 — pre-merge-commit 의 env 분기를 지우면 이 케이스가 붉어진다
#      (이 케이스가 없으면 병합 훅의 사용자-통과 분기가 뮤테이션에서 살아남는다: K2 3회전 생존자)
expect_committed "사용자 셸은 도장 없이도 병합 가능" 'env -u CLAUDECODE -u AI_AGENT git merge --no-ff --no-edit feat'

# 9) 알려진 한계를 잠근다(경계 핀): --no-verify 는 훅을 우회한다(설계상 수용된 표준 우회)
git reset -q --hard HEAD
uniq_stage c9
expect_committed "--no-verify 는 훅 우회(문서화된 한계)" 'git commit --no-verify -m x'

# 10) 비커밋 git 명령은 무관 — 도장 없어도 정상 종료
git reset -q --hard HEAD
git status >/dev/null 2>&1 || { echo "실패: 비커밋 git status 가 실패"; fail=1; }

# 11) 도장 스크립트 비실행 → pre-commit fail-closed 차단
uniq_stage c11
chmod -x .claude/scripts/review-stamp.sh
expect_blocked "도장 스크립트 비실행 시 차단" 'git commit -m x'
chmod +x .claude/scripts/review-stamp.sh

# 12) --verify 계약: 도장 없음/ git 없는 PATH 모두 fail-closed (훅이 실제 부르는 것은 --verify)
rm -f .claude/.kit-review-pass
if "$STAMP" --verify; then echo "실패[--verify]: 도장 없는데 0 반환"; fail=1; fi
if PATH=/nonexistent "$STAMP" --verify 2>/dev/null; then echo "실패[degrade]: git 없는데 --verify 가 0 반환"; fail=1; fi
if PATH=/nonexistent "$STAMP" --write  2>/dev/null; then echo "실패[degrade]: git 없는데 --write 가 도장을 찍었다"; fail=1; fi

# 12-b) 시그널 중단에 임시 인덱스가 남지 않는다 (이슈 #100 · #125)
#   1회전 리뷰에서 `trap` 을 붙였는데 **아무것도 정리하지 않았다** — `TMPIDX_DIR` 이 명령치환
#   서브셸에서만 대입돼 부모 핸들러는 늘 빈 값을 봤다. 게다가 `INT TERM HUP` 을 덧붙인 탓에
#   신호가 삼켜져 Ctrl-C 뒤에 **틀린 진단**까지 냈다. 그 회귀를 잡는 자리가 여기다.
sigdir="$(mktemp -d)"
mkdir -p "$sigdir/bin"
# git add 를 느리게 만들어 그 사이에 신호를 넣는다
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = add ] && sleep 5; done\nexec %s "$@"\n' \
  "$(command -v git)" > "$sigdir/bin/git"
chmod +x "$sigdir/bin/git"
before="$(ls -A "${TMPDIR:-/tmp}" | sort)"
# **별도 프로세스 그룹**에서 돌린다. `set -m` 없이 프로세스 그룹에 신호를 보내면
# 이 검사 스크립트 자신까지 죽는다(실측 exit 130).
env PATH="$sigdir/bin:$PATH" S="$STAMP" bash -c '
  set -m
  "$S" --write >/dev/null 2>&1 &
  p=$!
  sleep 2
  pg=$(ps -o pgid= -p $p 2>/dev/null | tr -d " ")
  self=$(ps -o pgid= -p $$ 2>/dev/null | tr -d " ")
  if [ -n "$pg" ] && [ "$pg" != "$self" ]; then kill -INT -"$pg" 2>/dev/null; else kill -INT "$p" 2>/dev/null; fi
  wait $p
' >/dev/null 2>&1 || true
sleep 1
after="$(ls -A "${TMPDIR:-/tmp}" | sort)"
leaked="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -c '^tmp\.' || true)"
if [ "${leaked:-0}" -gt 0 ]; then
  echo "실패[시그널]: SIGINT 로 죽은 뒤 임시 인덱스 디렉토리가 남았다 ($leaked 개)"
  fail=1
  comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") \
    | grep '^tmp\.' | while IFS= read -r x; do rm -rf "${TMPDIR:-/tmp:?}/$x"; done
fi
rm -rf "$sigdir"

# 13) 뮤테이션 자기검증 — 게이트를 끄면 '차단'됐던 커밋이 통과해야 한다(차단 판정이 hollow 가 아님을 증명)
git reset -q --hard HEAD
uniq_stage cmut
rm -f .claude/.kit-review-pass
b="$(git rev-parse HEAD)"; git commit -m x >/dev/null 2>&1 || true
[ "$(git rev-parse HEAD)" = "$b" ] || { echo "실패[뮤테이션 준비]: 정상 게이트가 안 막았다"; fail=1; }
printf '#!/usr/bin/env bash\nexit 0\n' > .githooks/pre-commit; chmod +x .githooks/pre-commit
git commit -m x >/dev/null 2>&1 || true
[ "$(git rev-parse HEAD)" != "$b" ] || { echo "실패[뮤테이션]: 게이트를 껐는데 커밋이 안 됐다 — 차단 판정이 hollow"; fail=1; }

if [ "$fail" = 0 ]; then echo "리뷰 게이트 검사 통과"; else exit 1; fi
