#!/usr/bin/env bash
# check-docs.sh 회귀 검사 — 임시 사본에 위반을 심어 **실제로 붉어지는지** 본다.
#
# 왜 있나 (이슈 #103): `check-docs.sh` 는 fixture 가 아니라 검사기 자신이라
# CI 는 "실물이 GREEN 이다"만 확인했다. 각 분기가 **붉어지는 증거**가 저장소에 0건이었고,
# 그 결과 1회전 리뷰에서 새로 넣은 검사 셋이 **무장해제 상태로 커밋 직전까지** 왔다.
# 루트 CLAUDE.md 에 "손으로 뮤테이션을 돌린다"고 적어 뒀지만, 손으로 돌린 확인은
# 저장소에 안 남고 다음 리팩터에 승계되지 않는다 — 그 정책이 바로 그 변경분에서 실패했다.
#
# 규칙 두 가지:
#  1) **exit code 만 보지 않는다.** 기대하는 **메시지**까지 단언한다 — 다른 이유로 붉어진 것을
#     "잡았다"로 오인하면 fixture 가 hollow 해진다 (이슈 #097 이 정확히 그 모양이었다).
#  2) **정상 사본이 통과하는 것**도 케이스다. 오탐이 생기면 검사 전체가 무뎌진다.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
# EXIT 단독이다. bash 3.2 는 EXIT 트랩만으로도 시그널에서 돌고, INT/TERM/HUP 을 덧붙이면
# 핸들러가 exit 를 안 하는 한 **신호를 삼켜** 스크립트가 계속 돈다 (이슈 #100 에서 실증).
trap 'rm -rf "$TMP"' EXIT

fail=0
ok() { printf '  통과  %s\n' "$*"; }
ng() { printf '  실패  %s\n' "$*"; fail=1; }

mkfx() { # 저장소 사본 하나를 만들고 경로를 낸다
  # **케이스마다 새 디렉토리다.** 이전 판본은 `n=$((n+1))` 을 썼는데 `d=$(mkfx)` 의 명령치환
  # 서브셸에서만 증가해 31 개 케이스가 `fx1` **한 디렉토리를 공유**했다. `tar -xf` 는 덮어쓰기만
  # 하고 삭제를 안 하므로 앞 케이스가 만든 파일이 뒤로 샜다 — 맨 앞의 green 케이스를 맨 뒤에
  # 그대로 붙이면 실패했다(2회전 K2·K3). 통과가 격리 덕이 아니라 **순서 덕**이었다.
  local d
  d="$(mktemp -d "$TMP/fx.XXXXXX")" || return 1
  ( cd "$ROOT" && tar --exclude=./.git --exclude=./manyfast_reference \
                      --exclude=./docs/reports --exclude=./node_modules -cf - . ) \
    | ( cd "$d" && tar -xf - )
  git -C "$d" init -q
  git -C "$d" add -A >/dev/null 2>&1
  printf '%s' "$d"
}

run() { ( cd "$1" && LC_ALL="${2-}" bash scripts/check-docs.sh 2>&1 ); }

expect_red() { # $1 설명  $2 fx  $3 기대 메시지 조각  [$4 LC_ALL]
  local out rc
  out="$(run "$2" "${4-}")"; rc=$?
  if [ "$rc" = 0 ]; then
    ng "$1 — 통과해 버렸다 (exit 0)"; return
  fi
  case "$out" in
    *"$3"*) ok "$1" ;;
    *) ng "$1 — 붉어지긴 했으나 기대 메시지가 없다: '$3'"; printf '%s\n' "$out" | head -5 | sed 's/^/        /' ;;
  esac
}

expect_green() { # $1 설명  $2 fx  [$3 LC_ALL]
  local out rc
  out="$(run "$2" "${3-}")"; rc=$?
  if [ "$rc" = 0 ]; then ok "$1"; else
    ng "$1 — 손대지 않았는데 붉어졌다 (오탐)"; printf '%s\n' "$out" | head -8 | sed 's/^/        /'
  fi
}

sub() { # 파일 안 문자열 치환 (고정 문자열, 1회). $4 에 all 을 주면 전부.
  python3 - "$1" "$2" "$3" "${4-one}" <<'PY'
import sys
p, old, new, how = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(p, encoding='utf-8').read()
assert old in s, "심을 자리를 못 찾았다: %r (fixture 앵커가 낡았다)" % old
open(p, 'w', encoding='utf-8').write(s.replace(old, new) if how == 'all' else s.replace(old, new, 1))
PY
}

echo "기준선"
d=$(mkfx); expect_green "손대지 않은 사본은 통과한다" "$d"
expect_green "C 로케일에서도 통과한다 (오탐 없음)" "$d" "C"

echo
echo "검사 1-c — 이 저장소 자신의 백틱 경로"
d=$(mkfx); sub "$d/STATUS.md" '`scripts/check-docs.sh`' '`scripts/does-not-exist.sh`'
expect_red "없는 경로를 잡는다" "$d" "깨진 참조(저장소 자신)"

d=$(mkfx); sub "$d/CLAUDE.md" '`.githooks/pre-commit`' '`.githooks/no-such-hook`'
expect_red "**무확장자** 경로도 잡는다 (절대 규칙 1의 장치 경로다 — #117)" "$d" "깨진 참조(저장소 자신)"

d=$(mkfx); printf '\n참조: `docs/가이드/없는파일.md`\n' >> "$d/CHANGELOG.md"
expect_red "한글이 섞인 경로도 잡는다 (#148)" "$d" "깨진 참조(저장소 자신)"

echo
echo "검사 5 — 「절 이름」 포인터"
d=$(mkfx); sub "$d/templates/dev-kit/docs/guides/ready.md" \
  '## Story 크기 — 어디서 멈추나' '## Story 크기 판정'
expect_red "헤딩 개명을 잡는다" "$d" "끊긴 절 포인터"
expect_red "**C 로케일에서도** 잡는다 (#101)" "$d" "끊긴 절 포인터" "C"

d=$(mkfx); sub "$d/templates/dev-kit/docs/guides/profiles.md" \
  '| Story 문서 | 생략' '| Story 산출물 | 생략'
expect_red "표 행 이름 개명을 잡는다 (#089 포인터 방어선)" "$d" "끊긴 절 포인터"

d=$(mkfx)
python3 - "$d" <<'PY'
import os, sys
root = sys.argv[1]
for dp, _, fns in os.walk(root):
    if '/.git' in dp: continue
    for fn in fns:
        if not fn.endswith('.md'): continue
        p = os.path.join(dp, fn)
        s = open(p, encoding='utf-8').read()
        if '「' in s:
            open(p, 'w', encoding='utf-8').write(s.replace('「', '“').replace('」', '”'))
PY
expect_red "추출이 0건이면 **통과로 위장하지 않는다** (#102)" "$d" "포인터를 한 건도 찾지 못했다"

d=$(mkfx); printf '\n자세한 것은 `docs/guides/ready.md` 라는 문서의 맨 마지막 절인 「없는 절 이름입니다」\n' >> "$d/CHANGELOG.md"
expect_red "연결 어구가 길어도 추출한다 (#146)" "$d" "끊긴 절 포인터"

d=$(mkfx); printf '\n권고임은 `docs/guides/ready.md` 「이 표에는 기계 장치가 없다」가 정본이다.\n' >> "$d/STATUS.md"
expect_green "인용구 안의 굵은 라벨 형태를 오탐하지 않는다 (#113)" "$d"

echo
echo "검사 6 — report.py 가 하드코딩한 절 이름"
d=$(mkfx); sub "$d/templates/dev-kit/.claude/scripts/report.py" \
  '"개발 준비 슬롯 — 12칸"' '"개발 준비 슬롯 — 없는 절"'
expect_red "없는 절 이름을 잡는다" "$d" "report.py"

d=$(mkfx); sub "$d/templates/dev-kit/docs/plan/cycles/C00-template.md" \
  '### 개발 준비 슬롯' '### 준비 슬롯 축약본'
expect_red "**대상 파일**을 해석한다 — 동명 헤딩에 가려지지 않는다 (#110)" "$d" "report.py"

echo
echo "검사 7 — 축 ↔ 에이전트"
d=$(mkfx); rm -f "$d/.claude/agents/kit-review-k3.md"
expect_red "표에 있는데 파일이 없으면 잡는다" "$d" "kit-review-k3"

d=$(mkfx); sub "$d/.claude/commands/kit-review.md" \
  '| K3 | `kit-review-k3` |' '| K3 | `kit-review-k9` |'
expect_red "표와 파일이 어긋나면 잡는다" "$d" "kit-review"

d=$(mkfx)
sub "$d/.claude/commands/kit-review.md" '| K2 | `kit-review-k2` |' '| K2 | `KREV-SWAP-A` |'
sub "$d/.claude/commands/kit-review.md" '| K3 | `kit-review-k3` |' '| K3 | `kit-review-k2` |'
sub "$d/.claude/commands/kit-review.md" '| K2 | `KREV-SWAP-A` |' '| K2 | `kit-review-k3` |'
expect_red "**축 열을 뒤바꾼 오배선**을 잡는다 (#131)" "$d" "축"

d=$(mkfx); sub "$d/.claude/agents/kit-review-k5.md" 'name: kit-review-k5' 'name: kit-review-k55'
expect_red "파일명과 frontmatter name 불일치를 잡는다" "$d" "name"

echo
echo "검사 8 — issues.md 이슈 번호 유일성"
# `issues.md` 는 `.gitignore` 대상이라 **CI 체크아웃에는 없다.** 실물에 append 하면
# 로컬에서만 도는 fixture 가 된다 — 실제로 그렇게 만들었다가 CI 에서 붉어졌다(#153).
# 그래서 **합성 issues.md 를 통째로 써 넣는다**: 실물 유무와 무관하게 같은 것을 잰다.
synth_issues() { # $1 = fixture 경로, $2 = 행 묶음
  { printf '# 이슈 로그 (합성)\n\n## 열린 이슈\n\n'
    printf '| # | 심각도 | 한 줄 | 출처 | 상태 |\n|---|---|---|---|---|\n'
    printf '%s\n' "$2"
  } > "$1/issues.md"
}

d=$(mkfx); synth_issues "$d" '| #001 | 높음 | 첫 줄 | 진단 | 열림 |
| #002 | 보통 | 둘째 줄 | 진단 | 열림 |
| #001 | 높음 | 같은 번호를 다시 썼다 | 진단 | 열림 |'
expect_red "중복 번호를 잡는다" "$d" "이슈 번호 중복"

d=$(mkfx); synth_issues "$d" '| #001 | 높음 | 첫 줄 | 진단 | 열림 |
|  #001  | 높음 | 공백 변형 중복 | 진단 | 열림 |'
expect_red "**공백 변형**도 잡는다 (#149)" "$d" "이슈 번호 중복"

d=$(mkfx); synth_issues "$d" '| #001 | 높음 | 첫 줄 | 진단 | 열림 |
| #002 | 보통 | 둘째 줄 | 진단 | 열림 |'
expect_green "번호가 유일하면 조용하다 (경계값)" "$d"

d=$(mkfx); synth_issues "$d" '| 2026 | #001 | 앞에 열이 하나 늘었다 | 진단 | 열림 |
| 2026 | #002 | 표 형식이 바뀌면 추출이 0건이 된다 | 진단 | 열림 |'
expect_red "이슈 행을 한 건도 못 찾으면 **통과로 위장하지 않는다** (#102)" "$d" "이슈 행을 한 건도 찾지 못했다"

d=$(mkfx); rm -f "$d/issues.md"
expect_green "issues.md 가 없으면(CI 가 그렇다) 조용히 건너뛴다" "$d"

echo
echo "검사 9 — Write 를 가진 에이전트의 임시 디렉토리 제한"
d=$(mkfx); sub "$d/.claude/agents/kit-review-k2.md" 'mktemp -d' '임시 디렉토리' all
expect_red "제한 문장이 사라지면 잡는다" "$d" "임시 디렉토리 제한"

d=$(mkfx)
python3 -c "
import sys; p=sys.argv[1]; s=open(p,encoding='utf-8').read()
open(p,'w',encoding='utf-8').write(s.replace('tools: Read, Grep, Glob, Bash, Write\n','',1).replace('mktemp -d','임시 디렉토리'))
" "$d/.claude/agents/kit-review-k2.md"
expect_red "**\`tools:\` 줄이 없어도** 대상이다 (도구 전체 상속 — #115①)" "$d" "임시 디렉토리 제한"

d=$(mkfx)
python3 -c "
import sys; p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s=s.replace('tools: Read, Grep, Glob, Bash, Write','tools:\n  - Read\n  - Bash\n  - Write',1)
open(p,'w',encoding='utf-8').write(s.replace('mktemp -d','임시 디렉토리'))
" "$d/.claude/agents/kit-review-k2.md"
expect_red "**YAML 블록 리스트** 표기도 대상이다 (#115②)" "$d" "임시 디렉토리 제한"

d=$(mkfx)
python3 -c "
import sys; p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s=s.replace('Glob, Bash, Write','Glob, Bash, Edit',1)
open(p,'w',encoding='utf-8').write(s.replace('mktemp -d','임시 디렉토리'))
" "$d/.claude/agents/kit-review-k2.md"
expect_red "**Edit** 도 쓰기 도구다 (#115③)" "$d" "임시 디렉토리 제한"

d=$(mkfx); mkdir -p "$d/.claude/agents/extra"
printf -- '---\nname: sneaky\ndescription: d\ntools: Read, Write\nmodel: inherit\n---\n\n본문\n' \
  > "$d/.claude/agents/extra/sneaky.md"
expect_red "**하위 디렉토리**의 에이전트도 본다 (#151)" "$d" "sneaky"

d=$(mkfx); rm -rf "$d/.claude/agents"
expect_red "에이전트 디렉토리가 없으면 **조용히 꺼지지 않는다** (#116)" "$d" "에이전트 디렉토리"

echo
echo "검사 10 — 이 저장소에서 밟은 셸 함정 (이슈 #104)"
# 함정 패턴을 이 파일에 **리터럴로** 담지 않는다 — 담으면 검사 10 이 자기 fixture 를 잡는다.
# 페이로드는 python3 이 코드포인트로 조립한다.
d=$(mkfx)
python3 -c 'import sys; open(sys.argv[1],"w",encoding="utf-8").write("#!/usr/bin/env bash\nsect=X\necho \"" + chr(0x300C) + "$sect" + chr(0x300D) + "\"\n")' "$d/scripts/probe-a.sh"
expect_red "\$변수 뒤 멀티바이트를 잡는다 (#097 재발)" "$d" "멀티바이트"

d=$(mkfx)
python3 -c 'import sys; open(sys.argv[1],"w",encoding="utf-8").write("#!/usr/bin/env bash\nawk -v n=\"" + "".join(map(chr,[0xAC00,0xB098,0xB2E4])) + "\" \x27BEGIN{ if (n == \"" + "".join(map(chr,[0xB77C,0xB9C8,0xBC14])) + "\") print 1 }\x27\n")' "$d/scripts/probe-b.sh"
expect_red "awk 한글 == 비교를 잡는다 (#098 재발)" "$d" "awk"

echo
if [ "$fail" = 0 ]; then
  echo "check-docs.sh 회귀 통과"
else
  echo "check-docs.sh 회귀 실패"
  exit 1
fi
