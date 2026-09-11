#!/usr/bin/env bash
# 플러그인 훅 회귀 검사 — 훅 셋을 **실제 입력으로 돌려서** 본다.
#
# 2.0.0 이 만든 분기 두 가지:
#  1) 플러그인 훅은 플러그인이 켜진 **모든** 저장소에서 돈다(사용자 범위 설치면 전부). 1.x 는 훅 파일이
#     키트 프로젝트에만 있었으므로, 같은 범위를 지키려고 훅은 키트 표식(docs/status/STATUS.md)이 있을 때만 판정한다.
#  2) 제품 루트는 훅 공용 `hooks/lib-root.sh` 가 정한다 — MDM_PROJECT_ROOT → CLAUDE_PROJECT_DIR → PWD 에서
#     출발해, 표식이 거기 없으면 **그 git 저장소 최상위까지** 위로 올라가며 찾는다(git 밖이면 출발점만).
#     하위 디렉토리에서 띄운 세션은 CLAUDE_PROJECT_DIR 가 그 하위 경로다(2026-09-11 `claude -p` 실측, #426).
#
# 재는 것:
#   - 표식 있는 저장소 → 막는다(rc=2) / 표식 없는 저장소 → 판정하지 않는다(rc=0)
#   - 하위 디렉토리 세션 → 위로 올라가 막는다 · MDM_PROJECT_ROOT 가 CLAUDE_PROJECT_DIR 보다 먼저다
#   - git 밖에서는 상위 디렉토리의 표식을 줍지 않는다
#   - status-updated 의 반복 차단 방지 마커가 **이미 있을 때** 지워지고 다음 종료는 다시 막힌다 —
#     GNU stat 에서 `stat -f` 가 stdout 에 파일시스템 블록을 찍어 마커가 영구히 남던 결함(#430)을
#     macOS 에서도 재도록 GNU 흉내 `stat` 을 PATH 앞에 둔다
# 마지막 뮤테이션은 표식 판정을 전부 들어내 「표식 없는 저장소가 막힌다」로 붉어지는지 본다.
#
# guard 훅 둘은 jq 가 없으면 경고만 남기고 통과한다 — 그 상태에서는 「막는다」를 잴 수 없으므로
# 건너뛰지 않고 **실패**한다. 조용히 안 도는 검사는 없는 검사다.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$ROOT/plugins/mdm/hooks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ok() { printf '  통과  %s\n' "$*"; }
ng() { printf '  실패  %s\n' "$*"; fail=1; }

command -v jq >/dev/null 2>&1 || { echo "  실패  jq 가 없어 guard 훅의 「막는다」를 잴 수 없다 — 설치 후 다시 돌린다"; exit 1; }

kit="$TMP/kit"; other="$TMP/other"; loose="$TMP/loose"
mkdir -p "$kit/docs/status" "$kit/docs/spec" "$kit/sub/deep" "$other/docs/spec" "$loose/docs/status" "$loose/child"
printf '# STATUS\n\n**최종 갱신**: 2000-01-01\n' > "$kit/docs/status/STATUS.md"     # 표식 + 오래된 날짜
printf '# STATUS\n' > "$loose/docs/status/STATUS.md"                              # git 밖 상위의 표식
for d in "$kit" "$other"; do git -C "$d" init -q; done
mkdir -p "$TMP/t"

# $1 훅  $2 cwd  $3 입력  [$4… 추가 환경 NAME=VAL] — MDM_PROJECT_ROOT 는 호출자 환경에서 새지 않게 먼저 지운다
run_hook() {
  local hook="$1" dir="$2" in="$3"; shift 3
  ( cd "$dir" && env -u MDM_PROJECT_ROOT CLAUDE_PROJECT_DIR="$dir" TMPDIR="$TMP/t" "$@" bash "$HOOKS/$hook" >/dev/null 2>"$TMP/err" <<<"$in" )
}

DEP='{"tool_name":"Bash","tool_input":{"command":"npm install left-pad"}}'
sec() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"A=1"}}' "$1"; }
STOP='{"stop_hook_active":false}'

echo "guard-dependency.sh"
run_hook guard-dependency.sh "$kit" "$DEP"; rc=$?
[ "$rc" = 2 ] && ok "키트 저장소: stack.md 없는 패키지 설치를 막는다 (rc=2)" || ng "키트 저장소에서 막지 않았다 (rc=$rc): $(head -1 "$TMP/err")"
run_hook guard-dependency.sh "$other" "$DEP"; rc=$?
[ "$rc" = 0 ] && ok "표식 없는 저장소: 같은 입력을 판정하지 않고 통과한다 (rc=0)" || ng "남의 저장소를 막았다 (rc=$rc)"
run_hook guard-dependency.sh "$kit/sub/deep" "$DEP"; rc=$?
[ "$rc" = 2 ] && ok "하위 디렉토리 세션(CLAUDE_PROJECT_DIR=kit/sub/deep): git 최상위까지 올라가 표식을 찾아 막는다 (#426)" || ng "하위 디렉토리 세션에서 막지 않았다 (rc=$rc)"
run_hook guard-dependency.sh "$other" "$DEP" MDM_PROJECT_ROOT="$kit"; rc=$?
[ "$rc" = 2 ] && ok "MDM_PROJECT_ROOT 가 CLAUDE_PROJECT_DIR 보다 먼저다 — 엔진과 같은 순서 (#431)" || ng "MDM_PROJECT_ROOT 를 보지 않았다 (rc=$rc)"
run_hook guard-dependency.sh "$loose/child" "$DEP"; rc=$?
[ "$rc" = 0 ] && ok "git 밖에서는 상위 디렉토리의 표식을 줍지 않는다 (출발점만 본다)" || ng "git 밖 상위의 표식으로 판정했다 (rc=$rc)"

echo "guard-secrets.sh"
run_hook guard-secrets.sh "$kit" "$(sec "$kit/.env")"; rc=$?
[ "$rc" = 2 ] && ok "키트 저장소: .env 쓰기를 막는다 (rc=2)" || ng "키트 저장소에서 막지 않았다 (rc=$rc): $(head -1 "$TMP/err")"
run_hook guard-secrets.sh "$other" "$(sec "$other/.env")"; rc=$?
[ "$rc" = 0 ] && ok "표식 없는 저장소: 같은 입력을 판정하지 않고 통과한다 (rc=0)" || ng "남의 저장소를 막았다 (rc=$rc)"
run_hook guard-secrets.sh "$kit/sub" "$(sec "$kit/sub/.env")"; rc=$?
[ "$rc" = 2 ] && ok "하위 디렉토리 세션: kit/sub/.env 쓰기를 막는다 (#426)" || ng "하위 디렉토리 세션에서 .env 쓰기를 막지 않았다 (rc=$rc)"

echo "status-updated.sh"
printf 'x' > "$kit/dirty.txt"; printf 'x' > "$other/dirty.txt"
rm -f "$TMP"/t/claude-status-guard-*
run_hook status-updated.sh "$kit" "$STOP"; rc=$?
[ "$rc" = 2 ] && ok "키트 저장소: 변경이 있는데 STATUS 가 오늘이 아니면 종료를 막는다 (rc=2)" || ng "키트 저장소에서 막지 않았다 (rc=$rc): $(head -1 "$TMP/err")"
rm -f "$TMP"/t/claude-status-guard-*
run_hook status-updated.sh "$other" "$STOP"; rc=$?
[ "$rc" = 0 ] && ok "표식 없는 저장소: 통과한다 (rc=0)" || ng "남의 저장소의 종료를 막았다 (rc=$rc)"

# 마커가 이미 있는 상태 — GNU 흉내 stat: `-f` 는 stdout 에 파일시스템 블록을 찍고 rc 1, `-c %Y` 는 수정 시각.
mkdir -p "$TMP/gnubin"
cat > "$TMP/gnubin/stat" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  -f) printf '  File: "%s"\n    ID: 0        Namelen: 255     Type: apfs\n' "${3:-}"; exit 1 ;;
  -c) exec date -r "$3" +%s ;;
esac
exit 1
SHIM
chmod +x "$TMP/gnubin/stat"
for flavor in native gnu; do
  rm -f "$TMP"/t/claude-status-guard-*
  pathv="$PATH"; [ "$flavor" = gnu ] && pathv="$TMP/gnubin:$PATH"
  run_hook status-updated.sh "$kit" "$STOP" PATH="$pathv"; r1=$?
  run_hook status-updated.sh "$kit" "$STOP" PATH="$pathv"; r2=$?
  left=$(ls "$TMP"/t/claude-status-guard-* 2>/dev/null | wc -l | tr -d ' ')
  run_hook status-updated.sh "$kit" "$STOP" PATH="$pathv"; r3=$?
  if [ "$r1" = 2 ] && [ "$r2" = 0 ] && [ "$left" = 0 ] && [ "$r3" = 2 ]; then
    ok "마커가 있을 때($flavor stat): 한 번 쉬고 마커를 지운 뒤 다음 종료는 다시 막는다 (#430)"
  else
    ng "마커 처리($flavor stat)가 틀렸다 — 차단 $r1 · 쉼 $r2(마커 남음 $left) · 다시 차단 $r3: $(head -1 "$TMP/err")"
  fi
done

echo "뮤테이션 자기검증 — 표식 판정을 전부 들어내면 표식 없는 저장소가 막혀야 한다"
mut="$TMP/mut"; cp -R "$HOOKS" "$mut"
python3 - "$mut" <<'PY'
import sys, os
d = sys.argv[1]
lib = os.path.join(d, 'lib-root.sh'); s = open(lib, encoding='utf-8').read()
anchor = '  return 1\n}\n'
assert s.count(anchor) >= 1, '뮤테이션 지점(lib-root.sh 의 마지막 return 1)을 못 찾았다'
i = s.rindex(anchor)
open(lib, 'w', encoding='utf-8').write(s[:i] + '  ROOT="$start"; return 0\n}\n' + s[i+len(anchor):])
st = os.path.join(d, 'status-updated.sh'); s = open(st, encoding='utf-8').read()
line = '[ -f "$STATUS" ] || exit 0'
assert line in s, '뮤테이션 지점(status-updated 의 STATUS 존재 검사)을 못 찾았다'
open(st, 'w', encoding='utf-8').write(s.replace(line, ':', 1))
PY
if [ $? != 0 ]; then ng "뮤테이션을 가하지 못했다 — 이 fixture 를 갱신한다"; else
  for h in guard-dependency.sh guard-secrets.sh status-updated.sh; do
    case "$h" in guard-dependency.sh) in="$DEP" ;; guard-secrets.sh) in="$(sec "$other/.env")" ;; *) in="$STOP" ;; esac
    rm -f "$TMP"/t/claude-status-guard-*
    ( cd "$other" && env -u MDM_PROJECT_ROOT CLAUDE_PROJECT_DIR="$other" TMPDIR="$TMP/t" bash "$mut/$h" >/dev/null 2>&1 <<<"$in" ); rc=$?
    [ "$rc" = 2 ] && ok "$h: 표식 판정을 빼면 남의 저장소가 막힌다 (fixture 가 진짜로 게이트를 재고 있다)" || ng "$h: 표식 판정을 뺐는데도 rc=$rc — 이 자기검증이 아무것도 재지 않는다"
  done
fi

echo
if [ "$fail" = 0 ]; then echo "훅 회귀 통과"; else echo "훅 회귀 실패"; exit 1; fi
