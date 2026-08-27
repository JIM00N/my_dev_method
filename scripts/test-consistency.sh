#!/usr/bin/env bash
# 정합성 검사 H(마일스톤 배치) 회귀 검사 — 임시 fixture 저장소에서 실측한다.
# "막는다·경고한다"는 약속의 증거가 이 파일이다 (루트 CLAUDE.md 절대 규칙 3).
#
# 검사기를 읽는 게 아니라 돌린다. 심는 결함마다 기대 신호를 요구하고,
# 마지막에 뮤테이션 자기검증으로 "fixture 가 아무거나 통과시키지 않는지"를 다시 못박는다.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/templates/dev-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
ok()  { printf '  통과  %s\n' "$*"; }
ng()  { printf '  실패  %s\n' "$*"; fail=1; }

# fixture 저장소 하나를 만든다. $1 = 매핑표 2절 데이터 행들(개행 구분)
make_fixture() {
  local rows="$1" d="$TMP/fx"
  rm -rf "$d"
  mkdir -p "$d/.claude/scripts" "$d/docs/spec" "$d/docs/upstream"
  cp "$KIT/.claude/scripts/check-consistency.sh" "$d/.claude/scripts/"
  chmod +x "$d/.claude/scripts/check-consistency.sh"

  printf 'prd.md\tself:plan\t2026-01-01\t%s\n' "$(: )" > /dev/null
  printf '# upstream\n' > "$d/docs/upstream/prd.md"
  # 스냅샷 무결성(검사 A)이 H 를 가리지 않도록 해시를 실제로 맞춰 둔다
  local h
  if command -v sha256sum >/dev/null 2>&1; then h=$(sha256sum "$d/docs/upstream/prd.md" | awk '{print $1}')
  else h=$(shasum -a 256 "$d/docs/upstream/prd.md" | awk '{print $1}'); fi
  printf 'prd.md\tself:plan\t2026-01-01T00:00:00Z\t%s\n' "$h" > "$d/docs/upstream/manifest.tsv"

  {
    printf '# source-map\n\n## 2. 요구사항 매핑표\n\n'
    printf '| ID | 출처 | 화면 | 준비 | 마일스톤 | 사이클 | 조건 수 | 테스트 | 상태 | 재검토 |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|\n'
    printf '%s\n' "$rows"
    printf '\n## 3. 화면 매핑표\n\n'
    printf '| ID | 이름 | 관련 요구사항 |\n|---|---|---|\n'
    printf '\n'
  } > "$d/docs/spec/source-map.md"
  printf '# interface\n' > "$d/docs/spec/interface.md"
  printf '%s' "$d"
}

run() { ( cd "$1" && bash .claude/scripts/check-consistency.sh 2>&1 ); }

# 기대 신호가 출력에 있어야 한다
expect_signal() { # $1 설명  $2 fixture경로  $3 기대 문자열
  local out; out="$(run "$2")"
  case "$out" in
    *"$3"*) ok "$1" ;;
    *) ng "$1 — 기대 신호가 없다: '$3'"; printf '%s\n' "$out" | sed 's/^/        /' ;;
  esac
}
expect_no_signal() { # $1 설명  $2 fixture경로  $3 없어야 할 문자열
  local out; out="$(run "$2")"
  case "$out" in
    *"$3"*) ng "$1 — 없어야 할 신호가 나왔다: '$3'"; printf '%s\n' "$out" | sed 's/^/        /' ;;
    *) ok "$1" ;;
  esac
}

echo "검사 H — 마일스톤 배치"

# H1. 배치가 비면 실패한다
d=$(make_fixture '| FR-1 | prd.md | — | ✅ | | C01 | 2 | — | ⬜ 대기 | — |')
expect_signal "H1 배치 빈 칸을 잡는다" "$d" "마일스톤 배치가 비었다"
d=$(make_fixture '| FR-1 | prd.md | — | ✅ | — | C01 | 2 | — | ⬜ 대기 | — |')
expect_signal "H1 배치가 '—' 여도 잡는다" "$d" "마일스톤 배치가 비었다"

# H2. 한 마일스톤에 사이클 6바퀴 → 경고
rows=''
for i in 1 2 3 4 5 6; do
  rows="${rows}| FR-$i | prd.md | — | ✅ | M1 | C0$i | 1 | — | ⬜ 대기 | — |
"
done
d=$(make_fixture "$rows")
expect_signal "H2 사이클 5바퀴 초과를 경고한다" "$d" "사이클이 6바퀴다"

# 5바퀴는 경고하지 않는다 (경계값 — 초과에서만 운다)
rows=''
for i in 1 2 3 4 5; do
  rows="${rows}| FR-$i | prd.md | — | ✅ | M1 | C0$i | 1 | — | ⬜ 대기 | — |
"
done
d=$(make_fixture "$rows")
expect_no_signal "H2 정확히 5바퀴는 조용하다" "$d" "바퀴다"

# H3. 요구사항 1개짜리 마일스톤 → 경고
d=$(make_fixture '| FR-1 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |
| FR-2 | prd.md | — | ✅ | M2 | C02 | 1 | — | ⬜ 대기 | — |')
expect_signal "H3 요구사항 1개 마일스톤을 경고한다" "$d" "요구사항이 1개뿐이다"

# 정상 배치는 H 신호를 내지 않는다
d=$(make_fixture '| FR-1 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |
| FR-3 | prd.md | — | ✅ | M2 | | 1 | — | ⬜ 대기 | — |
| FR-4 | prd.md | — | ✅ | M2 | | 1 | — | ⬜ 대기 | — |')
expect_no_signal "정상 배치는 H1 을 내지 않는다" "$d" "마일스톤 배치가 비었다"
expect_no_signal "정상 배치는 H3 을 내지 않는다" "$d" "요구사항이 1개뿐이다"

# 열이 없으면 건너뛴다고 말한다 (조용히 통과하지 않는다)
d=$(make_fixture '| FR-1 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
sed -i.bak 's/| 준비 | 마일스톤 |/| 준비 |/; s/| ✅ | M1 |/| ✅ |/' "$d/docs/spec/source-map.md"
expect_signal "마일스톤 열이 없으면 건너뛴다고 알린다" "$d" "'마일스톤' 열이 없다"

# 뮤테이션 자기검증 — 검사기에서 H 블록을 들어내면 위 fixture 들이 반드시 깨져야 한다.
echo "뮤테이션 자기검증"
d=$(make_fixture '| FR-1 | prd.md | — | ✅ | | C01 | 2 | — | ⬜ 대기 | — |')
python3 - "$d/.claude/scripts/check-consistency.sh" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
i = s.index('# ── H. 마일스톤 배치')
j = s.index('# ── 결과 ──', i)
open(p, 'w', encoding='utf-8').write(s[:i] + s[j:])
PY
out="$(run "$d")"
case "$out" in
  *"마일스톤 배치가 비었다"*) ng "H 를 들어냈는데도 신호가 났다 — fixture 가 검사기를 실측하지 않는다" ;;
  *) ok "H 를 들어내면 신호가 사라진다 (fixture 가 진짜로 H 를 재고 있다)" ;;
esac

echo
if [ "$fail" = 0 ]; then
  echo "정합성 검사 H 회귀 통과"
else
  echo "정합성 검사 H 회귀 실패"
  exit 1
fi
