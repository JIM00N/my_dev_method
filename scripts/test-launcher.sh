#!/usr/bin/env bash
# bin/mdm 런처 회귀 검사 — 런처를 **실제로 실행해서** 본다 (issues #425).
#
# 왜 있나: `mdm check`·`mdm final` 은 2.0.0 이 새로 만든 공개 검사 이름이고, 제품 CI 양식의 유일한 실행 줄과
# 모든 커맨드 문서가 이 진입점을 부른다. 그런데 런처를 실행하는 fixture 가 없어서 `SCRIPTS` 경로 오타로
# 런처가 rc=127 로 죽어도 이 저장소 CI 8스텝이 전부 GREEN 이었다(리뷰 반증 실측). 오타보다 무서운 것은
# 조용한 약화다 — `final` 이 인계 검사를 빼고 정합성만 돌게 바뀌어도 아무도 모른다.
#
# 재는 것:
#   1) 분기표 — 엔진을 **스텁**으로 바꾼 사본에서 명령마다 어느 스크립트가 어떤 인자로 불렸는지 (공백 인자 보존 포함).
#      `final` 은 정합성 → 인계 순서로 둘 다 부른다.
#   2) 실제 엔진 — version == plugin.json · root(하위 디렉토리에서 git 루트, MDM_PROJECT_ROOT 우선) ·
#      모르는 명령 rc 64 · 인자 없음은 사용법 · `check --init` 이 도입 전 신호를 낸다.
#   3) 제품 CI 양식 — 양식의 실행 줄을 yml 에서 **뽑아 그대로** 돌린다 (clone 대신 원본 저장소를 가리키는 링크).
#   4) 심볼릭 링크로 PATH 에 올린 런처도 돈다.
# 마지막 뮤테이션 자기검증은 런처의 SCRIPTS 경로를 망가뜨려 1) 이 붉어지는지 본다.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="$ROOT/plugins/mdm"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ok() { printf '  통과  %s\n' "$*"; }
ng() { printf '  실패  %s\n' "$*"; fail=1; }

VER=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")

# 스텁 엔진: 원본 플러그인을 복사하고, 런처가 부르는 대상을 「이름 + 인자(한 줄에 하나)」를 찍는 스텁으로 바꾼다.
# mdm-check.sh(= final)는 **진짜**를 둔다 — final 이 정합성과 인계를 둘 다 부르는지를 그 파일이 결정하기 때문이다.
make_stub() { # $1 = 대상 디렉토리 (그 아래 plugins/mdm)
  local d="$1/plugins/mdm" f
  mkdir -p "$1/plugins"; cp -R "$PLUGIN" "$d"; rm -rf "$d/scripts/__pycache__"
  for f in check-consistency.sh init-project.sh; do
    printf '#!/usr/bin/env bash\nprintf "STUB %s\\n"; for a in "$@"; do printf "ARG[%%s]\\n" "$a"; done\n' "$f" > "$d/scripts/$f"
  done
  for f in mdm-contract.py mdm-ops.py report.py; do
    printf 'import sys\nprint("STUB %s")\nfor a in sys.argv[1:]:\n    print("ARG[%%s]" %% a)\n' "$f" > "$d/scripts/$f"
  done
}

# 분기표 단언 — $1 = 런처 경로. 실패한 줄 수를 돌려준다(뮤테이션 자기검증이 같은 함수를 쓴다).
dispatch_failures() {
  local L="$1" n=0 out
  expect() { # $1 설명  $2… 런처 인자 ;  기대 출력은 전역 WANT
    local desc="$1"; shift
    out="$(MDM_PROJECT_ROOT="$TMP" bash "$L" "$@" 2>&1)"
    if [ "$out" = "$WANT" ]; then [ "${QUIET:-0}" = 1 ] || ok "$desc"; else
      n=$((n+1)); [ "${QUIET:-0}" = 1 ] || { ng "$desc"; printf '%s\n' "$out" | head -4 | sed 's/^/        /'; }
    fi
  }
  WANT=$'STUB check-consistency.sh\nARG[--init]\nARG[--scope]\nARG[ST 1]'
  expect "check → check-consistency.sh, 인자 그대로 (공백 든 인자 보존)" check --init --scope "ST 1"
  WANT=$'최종 통합 검사 — 제품: '"$TMP"$'\nSTUB check-consistency.sh\nSTUB mdm-ops.py\nARG[handoff-check]'
  expect "final → mdm-check.sh → 정합성 다음 인계 (둘 다, 이 순서)" final
  WANT=$'STUB mdm-contract.py\nARG[verify]\nARG[ST-1]\nARG[--]\nARG[sh -c x]'
  expect "contract → mdm-contract.py" contract verify ST-1 -- "sh -c x"
  WANT=$'STUB mdm-ops.py\nARG[handoff]\nARG[--note]\nARG[.tmp/a b.json]'
  expect "ops → mdm-ops.py" ops handoff --note ".tmp/a b.json"
  WANT=$'STUB report.py\nARG[ready]'
  expect "report → report.py" report ready
  WANT=$'STUB mdm-ops.py\nARG[doctor]\nARG[--run]'
  expect "doctor → mdm-ops.py doctor" doctor --run
  WANT=$'STUB init-project.sh\nARG[/p q]\nARG[--upgrade]'
  expect "init → init-project.sh" init "/p q" --upgrade
  return "$n"
}

echo "1. 분기표 (스텁 엔진)"
make_stub "$TMP/stub"
dispatch_failures "$TMP/stub/plugins/mdm/bin/mdm"

echo
echo "2. 실제 엔진"
prod="$TMP/prod"; mkdir -p "$prod"; git -C "$prod" init -q
bash "$PLUGIN/scripts/init-project.sh" "$prod" >/dev/null 2>&1 || ng "fixture 제품 설치 실패"
mkdir -p "$prod/src/deep"
L="$PLUGIN/bin/mdm"
out=$(env -u MDM_PROJECT_ROOT -u CLAUDE_PROJECT_DIR bash "$L" version 2>&1)
[ "$out" = "$VER" ] && ok "version = plugin.json version ($VER)" || ng "version 이 '$out' — plugin.json 은 $VER"
out=$(cd "$prod/src/deep" && env -u MDM_PROJECT_ROOT -u CLAUDE_PROJECT_DIR bash "$L" root 2>&1)
[ "$(cd "$out" 2>/dev/null && pwd -P)" = "$(cd "$prod" && pwd -P)" ] && ok "root: 하위 디렉토리에서 git 루트를 제품으로 본다" || ng "root 가 '$out'"
out=$(cd "$prod/src/deep" && MDM_PROJECT_ROOT="$prod/src" bash "$L" root 2>&1)
[ "$(cd "$out" 2>/dev/null && pwd -P)" = "$(cd "$prod/src" && pwd -P)" ] && ok "root: MDM_PROJECT_ROOT 가 git 루트보다 먼저다" || ng "MDM_PROJECT_ROOT 를 무시했다: '$out'"
bash "$L" bogus >/dev/null 2>"$TMP/err"; rc=$?
[ "$rc" = 64 ] && grep -q '사용법' "$TMP/err" && ok "모르는 명령은 rc 64 + 사용법(stderr)" || ng "모르는 명령 rc=$rc"
out=$(bash "$L" 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '사용법' && ok "인자 없음은 사용법을 보이고 rc 0" || ng "인자 없음 rc=$rc"
out=$(cd "$prod" && env -u MDM_PROJECT_ROOT -u CLAUDE_PROJECT_DIR bash "$L" check --init 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '도입 전' && ok "check --init: 실제 엔진이 새 제품을 「도입 전」으로 판정한다" || ng "check --init rc=$rc: $(printf '%s' "$out" | tail -1)"

echo
echo "3. 제품 CI 양식의 실행 줄"
yml="$PLUGIN/templates/.github/workflows/mdm-check.yml"
line=$(python3 - "$yml" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
runs = re.findall(r'^\s*run:\s*(.+bin/mdm.+)$', s, re.M)
print(runs[-1] if runs else '')
PY
)
if [ -z "$line" ]; then ng "양식에서 bin/mdm 을 부르는 run 줄을 찾지 못했다 — 추출이 깨졌다 (통과로 위장하지 않는다)"; else
  mkdir -p "$TMP/runner"; ln -s "$ROOT" "$TMP/runner/mdm"      # clone 대신 원본 저장소를 그 자리에
  out=$(cd "$prod" && RUNNER_TEMP="$TMP/runner" MDM_PROJECT_ROOT="$prod" bash -c "$line" 2>&1); rc=$?
  if printf '%s' "$out" | grep -q "최종 통합 검사 — 제품: $prod" && [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'MDM_MODEL'; then
    ok "양식의 실행 줄(\`$line\`)이 런처를 거쳐 실제 엔진으로 그 제품을 판정한다 (도입 전이라 rc 1 이 정답)"
  else
    ng "양식의 실행 줄이 뜻대로 돌지 않았다 (rc=$rc): $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  fi
fi

echo
echo "4. 심볼릭 링크로 PATH 에 올린 런처"
mkdir -p "$TMP/lnbin"; ln -s "$PLUGIN/bin/mdm" "$TMP/lnbin/mdm"
out=$(PATH="$TMP/lnbin:$PATH" mdm version 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$out" = "$VER" ] && ok "링크 경유 \`mdm version\` 이 돈다 (#456)" || ng "링크 경유 실패 rc=$rc: $(printf '%s' "$out" | tail -1)"

echo
echo "뮤테이션 자기검증 — 런처의 SCRIPTS 경로를 망가뜨리면 분기표가 붉어져야 한다"
make_stub "$TMP/mut"
python3 - "$TMP/mut/plugins/mdm/bin/mdm" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
a = 'SCRIPTS="$HERE/../scripts"'
assert s.count(a) == 1, '뮤테이션 지점(SCRIPTS=…)을 못 찾았다'
open(p, 'w', encoding='utf-8').write(s.replace(a, 'SCRIPTS="$HERE/../script"'))
PY
if [ $? != 0 ]; then ng "뮤테이션을 가하지 못했다 — 이 fixture 를 갱신한다"; else
  QUIET=1 dispatch_failures "$TMP/mut/plugins/mdm/bin/mdm"; n=$?
  [ "$n" -ge 7 ] && ok "SCRIPTS 오타 뮤턴트에서 분기표 7개가 전부 붉어진다" || ng "뮤턴트에서 붉어진 것이 $n/7 — 이 fixture 가 런처를 재지 않는다"
fi

echo
if [ "$fail" = 0 ]; then echo "런처 회귀 통과"; else echo "런처 회귀 실패"; exit 1; fi
