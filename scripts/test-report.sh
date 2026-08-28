#!/usr/bin/env bash
# report.py 회귀 검사 — 임시 fixture 저장소에서 실제로 리포트를 생성해 내용을 본다.
#
# 겨냥하는 결함(이슈 #090): `story_slots()` 가 Story 문서를 하나라도 찾으면 사이클 문서의
# **축약 슬롯을 안 봤다**. Story 문서와 축약 슬롯은 배타가 아니라 **공존**한다 —
# 어떤 항목이 문서를 갖는지는 `docs/guides/profiles.md` 「Story 문서」 행이 정하고,
# Standard 는 일부만 문서를 가지므로 나머지는 사이클 문서에 남는다.
# 그 모드에서 리포트가 반쪽이 되면 `/mdm-ready` DoD 의 "리포트를 확인했다"가
# **보지 못한 슬롯을 확인한 것으로** 통과한다.
#
# 검사기를 읽는 게 아니라 돌린다. 마지막의 뮤테이션 자기검증이
# "이 fixture 가 진짜로 그 분기를 재고 있는지"를 못박는다 (루트 CLAUDE.md 절대 규칙 3).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/templates/dev-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
ok() { printf '  통과  %s\n' "$*"; }
ng() { printf '  실패  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "python3 가 없어 report.py 회귀 검사를 건너뛴다"; exit 0; }

# 공존 모드 fixture: Story 문서 1개 + 사이클 문서의 축약 슬롯 1개.
# (Standard 프로파일의 실제 모습이다 — 권한 영향분만 문서를 갖고 나머지는 사이클에 남는다)
make_fixture() {
  local d="$TMP/fx"
  rm -rf "$d"
  mkdir -p "$d/.claude/scripts" "$d/docs/plan/stories" "$d/docs/plan/cycles" \
           "$d/docs/spec" "$d/docs/guides" "$d/docs/status"
  cp "$KIT/.claude/scripts/report.py" "$d/.claude/scripts/"

  printf '# fixture 프로젝트\n' > "$d/CLAUDE.md"

  # Story 문서 — 1-1절이 개발 준비 슬롯이다
  cat > "$d/docs/plan/stories/ST-001-permission.md" <<'MD'
# ST-001 — 권한 영향이 있는 Story

## 1-1. 개발 준비 슬롯

| 슬롯 | 값 |
|---|---|
| 트리거 | STORY_DOC_SLOT_MARKER |

## 2. 영향 범위
MD

  # 사이클 문서 — 문서를 만들지 않은 항목의 축약 슬롯
  cat > "$d/docs/plan/cycles/C01-first.md" <<'MD'
# C01 — 첫 사이클

## 이번에 만들 것

### 개발 준비 슬롯 (Story 문서를 만들지 않는 항목) ★

| 항목 | 트리거 | 결과 |
|---|---|---|
| 목록 보기 | CYCLE_SHORT_SLOT_MARKER | 목록이 뜬다 |

## 이번에 만들지 않을 것

NEXT_SECTION_MARKER — 이 줄은 축약 슬롯 절에 딸려 들어오면 안 된다 (#121)
MD

  printf '# ready\n\n## 개발 준비 슬롯 — 12칸\n\n열두 칸의 뜻.\n' > "$d/docs/guides/ready.md"

  printf '# STATUS\n\n## 지금 하고 있는 일\n\n첫 사이클.\n' > "$d/docs/status/STATUS.md"
  printf '# source-map\n' > "$d/docs/spec/source-map.md"
  printf '%s' "$d"
}

gen() { ( cd "$1" && python3 .claude/scripts/report.py ready >/dev/null 2>&1 && cat docs/reports/ready-*.html ); }

echo "report.py — 개발 준비 슬롯 공존 모드"

d=$(make_fixture)
html_out="$(gen "$d")"

case "$html_out" in
  *STORY_DOC_SLOT_MARKER*) ok "Story 문서의 1-1절 슬롯이 리포트에 나온다" ;;
  *) ng "Story 문서의 슬롯이 리포트에 없다" ;;
esac
case "$html_out" in
  *CYCLE_SHORT_SLOT_MARKER*) ok "공존 모드에서 사이클 문서의 축약 슬롯도 함께 나온다 (#090)" ;;
  *) ng "축약 슬롯이 빠졌다 — Story 문서가 있으면 사이클 쪽을 건너뛰는 결함(#090)이 되살아났다" ;;
esac

case "$html_out" in
  *NEXT_SECTION_MARKER*) ng "축약 슬롯 절이 뒤따르는 \`##\` 절까지 끌어왔다 — pick_sections 의 끊는 조건이 얕다 (#121)" ;;
  *) ok "축약 슬롯 절이 다음 \`##\` 절을 넘지 않는다 (#121)" ;;
esac

# Lite 모드 — Story 문서가 아예 없어도 축약 슬롯은 나와야 한다 (원래 폴백이 죽지 않았는지)
d2=$(make_fixture)
rm -f "$d2/docs/plan/stories/ST-001-permission.md"
html2="$(gen "$d2")"
case "$html2" in
  *CYCLE_SHORT_SLOT_MARKER*) ok "Lite(Story 문서 없음)에서도 축약 슬롯이 나온다" ;;
  *) ng "Story 문서가 없는데 축약 슬롯도 안 나온다" ;;
esac

# 뮤테이션 자기검증 — 옛 조기 반환(`if out: return`)을 되살리면 위 공존 케이스가 반드시 깨져야 한다.
echo "뮤테이션 자기검증"
d3=$(make_fixture)
python3 - "$d3/.claude/scripts/report.py" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
# story_slots() 안, 사이클 문서를 훑기 시작하는 줄 바로 앞에 옛 조기 반환을 되살린다
anchor = '    # 사이클 문서의 축약 슬롯'
assert anchor in s, 'story_slots() 의 사이클 블록 주석을 찾지 못했다 — 뮤테이션 지점을 갱신한다'
s = s.replace(anchor, '    if out:\n        return "\\n".join(out)\n' + anchor, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
html3="$(gen "$d3")"
case "$html3" in
  *CYCLE_SHORT_SLOT_MARKER*) ng "조기 반환을 되살렸는데도 축약 슬롯이 나왔다 — fixture 가 이 분기를 실측하지 않는다" ;;
  *) ok "조기 반환을 되살리면 축약 슬롯이 사라진다 (fixture 가 진짜로 #090 을 재고 있다)" ;;
esac

echo
if [ "$fail" = 0 ]; then
  echo "report.py 회귀 통과"
else
  echo "report.py 회귀 실패"
  exit 1
fi
