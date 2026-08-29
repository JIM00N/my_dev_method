#!/usr/bin/env bash
# 정합성 검사 회귀 검사 — 임시 fixture 저장소에서 실측한다.
#   H. 마일스톤 배치
#   B·C 안의 **준비도 롤업 4분기**(실패 3 · 경고 1)와 열 부재 (이슈 #091)
#   I. 문서 등재 대조 — 미등재 문서 3유형 · 문서 없는 행 2유형 · 닫힌 Story 행 잔존 · 오탐 경계 2종
#   J. 계획 깊이 — 사양 표(영향 영역·선행·먼저·첫 묶음 동작) · 기능 층 · 권한 표 · self:plan 경계
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

  printf '# upstream\n' > "$d/docs/upstream/prd.md"
  # 스냅샷 무결성(검사 A)이 H 를 가리지 않도록 해시를 실제로 맞춰 둔다.
  # 출처는 **외부 상류**로 둔다 — 계획 깊이 검사(J)는 self:plan 한정이라, 여기서 self:plan 이면
  # H·준비도·I 를 재는 모든 fixture 가 J 신호까지 함께 내서 무엇을 재는지 흐려진다.
  # J 자신의 fixture 는 아래 make_plan 이 따로 깐다.
  local h
  if command -v sha256sum >/dev/null 2>&1; then h=$(sha256sum "$d/docs/upstream/prd.md" | awk '{print $1}')
  else h=$(shasum -a 256 "$d/docs/upstream/prd.md" | awk '{print $1}'); fi
  printf 'prd.md\trepo:docs/PRD.md\t2026-01-01T00:00:00Z\t%s\n' "$h" > "$d/docs/upstream/manifest.tsv"

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

echo
echo "준비도 롤업 — 매핑표 '준비' 칸 (이슈 #091)"

# 진행 중(🔵·🟡·✅)인데 준비 칸이 답을 못 준 세 가지는 **실패**다.
# (문서는 오래 "빈 칸이면 경고"라고 적었는데 코드는 실패였다 — 그래서 문서만 고치고 끝내지 않는다)
d=$(make_fixture '| FR-1 | prd.md | — | | M1 | C01 | 1 | — | 🔵 진행 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
expect_signal "진행 중 + 빈 칸 → 실패" "$d" "진행 중인데 준비도 점검을 안 돌렸다"

d=$(make_fixture '| FR-1 | prd.md | — | ❌ 재판정 | M1 | C01 | 1 | — | 🟡 검수 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
expect_signal "진행 중 + 재판정 → 실패" "$d" "상류가 바뀌어 준비 판정이 무효가 됐다"

# ❌ 는 재판정보다 **뒤에** 검사된다 — "❌ 재판정" 이 ❌ 분기로 새지 않는지도 위에서 함께 못박았다
d=$(make_fixture '| FR-1 | prd.md | — | ❌ 슬롯 3칸 빔 | M1 | C01 | 1 | — | 🔵 진행 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
expect_signal "진행 중 + ❌ → 실패" "$d" "준비되지 않은 칸이 남아 있다"

# 아직 진행 전(⬜·⛔)이면 같은 빈 칸이 **경고**다 — 등급이 뒤바뀌면 사이클이 헛돌거나 헛막힌다
d=$(make_fixture '| FR-1 | prd.md | — | | M1 | C01 | 1 | — | ⬜ 대기 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
expect_signal "진행 전 + 빈 칸 → 경고" "$d" "준비도 점검 전이다"
expect_no_signal "진행 전 빈 칸을 실패로 올리지 않는다" "$d" "진행 중인데 준비도 점검을 안 돌렸다"

# `—`·`-` 는 이 표 자신의 「해당 없음」 기호다 — 준비 칸에서 **답으로 받아서는 안 된다** (이슈 #150).
# 마일스톤 칸은 이미 그렇게 보는데 준비 칸만 달라서, 진행 중인 요구사항이 조용히 통과했다.
for v in '—' '-'; do
  d=$(make_fixture "| FR-1 | prd.md | — | $v | M1 | C01 | 1 | — | 🔵 진행 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |")
  expect_signal "진행 중 + '$v' → 실패 (마일스톤 칸과 같은 정의)" "$d" "진행 중인데 준비도 점검을 안 돌렸다"
done

# 채워져 있으면 조용하다 (경계값 — 정상 입력에서 울면 검사가 무뎌진다)
d=$(make_fixture '| FR-1 | prd.md | — | ✅ ST-001 | M1 | C01 | 1 | — | 🔵 진행 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
expect_no_signal "채워진 준비 칸은 조용하다" "$d" "준비"

# '준비' 열 자체가 없으면 **검사가 통째로 꺼진다** — 조용히 꺼지지 않고 알린다
d=$(make_fixture '| FR-1 | prd.md | — | | M1 | C01 | 1 | — | 🔵 진행 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
sed -i.bak 's/| 화면 | 준비 |/| 화면 |/; s/| — | | M1 |/| — | M1 |/; s/| — | ✅ | M1 |/| — | M1 |/' \
  "$d/docs/spec/source-map.md"
expect_signal "'준비' 열이 없으면 건너뛴다고 알린다" "$d" "'준비' 열이 없다"
expect_no_signal "열이 없으면 준비도 실패를 내지 않는다" "$d" "진행 중인데 준비도 점검을 안 돌렸다"

echo
echo "검사 I — 문서 등재 대조"

# 레지스트리 3개(사이클 현황·ADR 목록·활성 병렬 작업)와 양식 파일을 깐다. make_fixture 다음에 부른다.
# $1=fixture 경로  $2=사이클 표 행  $3=ADR 표 행  $4=활성 병렬 작업 표 행 (비면 자리만 깐다)
add_registries() {
  local d="$1"
  mkdir -p "$d/docs/plan/cycles" "$d/docs/plan/archive/cycles" \
           "$d/docs/plan/stories" "$d/docs/plan/archive/stories" \
           "$d/docs/decisions" "$d/docs/status"
  { printf '# plan\n\n## 사이클 현황\n\n| # | 이름 | 상태 |\n|---|---|---|\n| — | | |\n'
    [ -z "${2:-}" ] || printf '%s\n' "$2"; } > "$d/docs/plan/index.md"
  { printf '# decisions\n\n## 목록\n\n| # | 제목 | 상태 |\n|---|---|---|\n| — | | |\n'
    [ -z "${3:-}" ] || printf '%s\n' "$3"; } > "$d/docs/decisions/index.md"
  { printf '# STATUS\n\n## 활성 병렬 작업\n\n활성 Story 만 한 줄씩 적는 표다.\n\n| ID | 작업 | 상태 |\n|---|---|---|\n| — | | |\n'
    [ -z "${4:-}" ] || printf '%s\n' "$4"; } > "$d/docs/status/STATUS.md"
  # 양식 파일은 검사 대상이 아니어야 한다 — 실제 설치 상태처럼 항상 깔아 둔다
  printf '# 양식\n' > "$d/docs/plan/cycles/C00-template.md"
  printf '# 양식\n' > "$d/docs/plan/stories/ST-000-template.md"
  printf '# 양식\n' > "$d/docs/decisions/ADR-000-template.md"
}

# H·준비도가 조용한 기본 행 — I 의 신호만 남게 한다
I_BASE='| FR-1 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |'

# I1. 문서는 있는데 행이 없다 → 실패 (세 유형 각각)
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
expect_signal "I1 미등재 사이클 문서를 잡는다" "$d" "사이클 현황 표에 행이 없다"

d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '# ADR-001\n' > "$d/docs/decisions/ADR-001-db.md"
expect_signal "I1 미등재 ADR 문서를 잡는다" "$d" "목록 표에 행이 없다"

d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '# ST-001\n' > "$d/docs/plan/stories/ST-001-import.md"
expect_signal "I1 미등재 활성 Story 문서를 잡는다" "$d" "활성 병렬 작업 표에 행이 없다"

# I2. 행은 있는데 문서가 없다 → 실패 (사이클·ADR. Story 는 I4 — 문서 없는 행이 정상인 프로파일이 있다)
d=$(make_fixture "$I_BASE"); add_registries "$d" '| C02 | 유령 | 🔵 |' '| ADR-002 | 유령 | 채택 |'
expect_signal "I2 문서 없는 사이클 행을 잡는다" "$d" "행은 있는데 사이클 문서가 없다"
expect_signal "I2 문서 없는 ADR 행을 잡는다" "$d" "ADR 목록 표에 행은 있는데 문서가 없다"

# I3. archive 로 닫힌 Story 의 행이 활성 표에 남아 있다 → 실패
d=$(make_fixture "$I_BASE"); add_registries "$d" '' '' '| ST-002 | 닫힌 것 | ✅ |'
printf '# ST-002\n' > "$d/docs/plan/archive/stories/ST-002-old.md"
expect_signal "I3 닫힌 Story 의 잔존 행을 잡는다" "$d" "행이 남아 있다"

# I4. 문서 없는 Story 행은 잡지 않는다 — 프로파일에 따라 Story 는 문서 없이
#     사이클 문서에만 존재하는 것이 정상이다. 잡으면 설계상 오탐이 정상인 검사가 된다.
d=$(make_fixture "$I_BASE"); add_registries "$d" '' '' '| ST-009 | 문서 없는 Lite Story | 🔵 |'
expect_no_signal "I4 문서 없는 Story 행을 오탐하지 않는다" "$d" "ST-009"

# I5. 맞는 등재는 조용하다 — archive 사이클도 행이 있으면 통과(행 영구) · 양식 파일은 대상 아님
d=$(make_fixture "$I_BASE"); add_registries "$d" '| C01 | 첫 | 🔵 |
| C03 | 끝 | ✅ |' '| ADR-001 | DB | 채택 |' '| ST-001 | 가져오기 | 🔵 |'
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
printf '# C03\n' > "$d/docs/plan/archive/cycles/C03-done.md"
printf '# ADR-001\n' > "$d/docs/decisions/ADR-001-db.md"
printf '# ST-001\n' > "$d/docs/plan/stories/ST-001-import.md"
expect_no_signal "I5 맞는 등재는 조용하다 (archive 사이클 행 영구 포함)" "$d" "행이 없다"
expect_no_signal "I5 양식 파일(C00·ST-000·ADR-000)은 대상이 아니다" "$d" "000"

echo
echo "검사 I — 리뷰 1회전 적발분 (K2 치명·높음 / K3·K6 보통)"

# R1. [K2 치명 — 반증 확정] 매핑표 셀의 <br> 이 data_rows 의 플레이스홀더 필터(grep -v '<')에
#     걸려 전 행이 양식으로 오분류 → 「도입 전」 오판 + exit 0 → 검사 전체(A~I)가 꺼지고 거짓 보고.
#     <br> 은 마크다운 표 셀의 표준 줄바꿈이고, mdm-adopt --sync 의 재검토 나열이 유도하는 입력이다.
d=$(make_fixture '| FR-1 | prd.md | SC-1<br>SC-2 | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |
| FR-2 | prd.md | SC-3<br>SC-4 | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
add_registries "$d"
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
expect_no_signal "R1 셀 <br> 을 도입 전으로 오판하지 않는다" "$d" "도입 전"
expect_signal "R1 셀 <br> 이 있어도 검사 I 는 돈다" "$d" "사이클 현황 표에 행이 없다"

# R2. [K2 높음] 표 뒤 빈 줄 다음에 붙은 유령 행 — reg_table 이 첫 비-표 줄에서 끊겨 못 읽던 것
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '\n| C02 | 유령 | 🔵 |\n' >> "$d/docs/plan/index.md"
expect_signal "R2 빈 줄 뒤 유령 사이클 행을 잡는다" "$d" "행은 있는데 사이클 문서가 없다"

# R3. [K2 높음] 같은 절의 둘째 표 유령 행 (렌더링상 정상인 이어붙임 표)
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '\n이어서:\n\n| # | 이름 | 상태 |\n|---|---|---|\n| C02 | 유령 | 🔵 |\n' >> "$d/docs/plan/index.md"
expect_signal "R3 둘째 표의 유령 사이클 행을 잡는다" "$d" "행은 있는데 사이클 문서가 없다"

# R4. [K2 높음] 빈 줄 뒤 잔존 Story 행 — Lite 에서는 반대 방향 신호도 없어 완전 무음이던 것
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '\n| ST-002 | 닫힘 | ✅ |\n' >> "$d/docs/status/STATUS.md"
printf '# ST-002\n' > "$d/docs/plan/archive/stories/ST-002-old.md"
expect_signal "R4 빈 줄 뒤 잔존 Story 행을 잡는다" "$d" "행이 남아 있다"

# R5. [K2 보통] 꾸민 ID(볼드·백틱)의 행 — 판정 제외 필터가 유령·잔존 행을 통째로 면제하던 것
d=$(make_fixture "$I_BASE"); add_registries "$d" '| **C02** | 유령 | 🔵 |'
expect_signal "R5 볼드 ID 유령 사이클 행을 잡는다" "$d" "행은 있는데 사이클 문서가 없다"
d=$(make_fixture "$I_BASE"); add_registries "$d" '' '' '| **ST-002** | 닫힘 | ✅ |'
printf '# ST-002\n' > "$d/docs/plan/archive/stories/ST-002-old.md"
expect_signal "R5 볼드 ID 잔존 Story 행을 잡는다" "$d" "행이 남아 있다"

# R6. [K2·K3 보통] 열 이름이 다르면 조용히 꺼지던 것 — B·H 처럼 「건너뛴다」를 알린다
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '# plan\n\n## 사이클 현황\n\n| 번호 | 이름 | 상태 |\n|---|---|---|\n| C02 | 유령 | 🔵 |\n' > "$d/docs/plan/index.md"
expect_signal "R6 '#' 열이 없으면 알린다 (조용히 꺼지지 않는다)" "$d" "열이 없다"

# R7. [K2 보통] 코드펜스 안의 절 제목 예시가 먼저 매치돼 진짜 표를 놓치던 것
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '# STATUS\n\n예시:\n\n```\n## 활성 병렬 작업\n| ID | 작업 |\n|---|---|\n| — | |\n```\n\n## 활성 병렬 작업\n\n| ID | 작업 | 상태 |\n|---|---|---|\n| ST-002 | 닫힘 | ✅ |\n' > "$d/docs/status/STATUS.md"
printf '# ST-002\n' > "$d/docs/plan/archive/stories/ST-002-old.md"
expect_signal "R7 코드펜스 예시를 지나 진짜 표의 잔존 행을 잡는다" "$d" "행이 남아 있다"

# R8. [K3 보통] '#' 칸의 순번 숫자 행(| 3 |)을 C 접두 없이도 문서 없음으로 오탐하던 것
d=$(make_fixture "$I_BASE"); add_registries "$d" '| 3 | 메모 행 | — |'
expect_no_signal "R8 순번 숫자 행을 오탐하지 않는다" "$d" "행은 있는데 사이클 문서가 없다"

# R9. [K3 보통] 후행 개행 없는 마지막 줄 — 양방향으로 틀리던 것
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '# C05\n' > "$d/docs/plan/cycles/C05-last.md"
printf '| C05 | 마지막 | 🔵 |' >> "$d/docs/plan/index.md"   # 개행 없이 끝
expect_no_signal "R9 개행 없는 마지막 줄의 정상 등재를 오탐하지 않는다" "$d" "행이 없다"
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '| C02 | 유령 | 🔵 |' >> "$d/docs/plan/index.md"   # 개행 없이 끝
expect_signal "R9 개행 없는 마지막 줄의 유령 행을 잡는다" "$d" "행은 있는데 사이클 문서가 없다"

# R10. [K6 보통] 도입 전 조기 종료 — fixture 가 없어 블록 제거 회귀를 못 잡던 것
d="$TMP/fx"; rm -rf "$d"
mkdir -p "$d/.claude/scripts" "$d/docs/spec"
cp "$KIT/.claude/scripts/check-consistency.sh" "$d/.claude/scripts/"
chmod +x "$d/.claude/scripts/check-consistency.sh"
add_registries "$d"
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
out="$(run "$d")"; rc=$?
case "$out" in
  *"도입 전"*) ok "R10 소스맵 없으면 도입 전을 알리고 선다" ;;
  *) ng "R10 — '도입 전' 안내가 없다"; printf '%s\n' "$out" | sed 's/^/        /' ;;
esac
if [ "$rc" = 0 ]; then ok "R10 도입 전은 exit 0 이다"; else ng "R10 — 도입 전인데 rc=$rc"; fi
case "$out" in
  *"행이 없다"*) ng "R10 — 도입 전인데 검사 I 가 발화했다" ;;
  *) ok "R10 도입 전에는 검사 I 도 쉰다" ;;
esac

# R11. [K6 낮음] 일치 완화(grep -qx → -q) 생존 — C010 행은 C01 문서의 등재가 아니다
d=$(make_fixture "$I_BASE"); add_registries "$d" '| C010 | 열째 | 🔵 |'
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
printf '# C010\n' > "$d/docs/plan/cycles/C010-tenth.md"
expect_signal "R11 C010 행은 C01 의 등재로 안 쳐준다" "$d" "C01 — 사이클 문서는 있는데"

# R12. [K6 보통] I5 가 역방향 오탐(archive 글롭 제거 류)을 못 잡던 것 — 통과 상태를 직접 단언
d=$(make_fixture "$I_BASE"); add_registries "$d" '| C01 | 첫 | 🔵 |
| C03 | 끝 | ✅ |' '| ADR-001 | DB | 채택 |' '| ST-001 | 가져오기 | 🔵 |'
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
printf '# C03\n' > "$d/docs/plan/archive/cycles/C03-done.md"
printf '# ADR-001\n' > "$d/docs/decisions/ADR-001-db.md"
printf '# ST-001\n' > "$d/docs/plan/stories/ST-001-import.md"
expect_signal "R12 맞는 등재는 「통과」를 낸다" "$d" "정합성 검사 통과"
expect_no_signal "R12 맞는 등재에 역방향 오탐이 없다 (사이클)" "$d" "문서가 없다"
expect_no_signal "R12 맞는 등재에 역방향 오탐이 없다 (Story)" "$d" "행이 남아 있다"

echo
echo "검사 I·매핑표 — 리뷰 2회전 적발분 (K2 높음 3 확정 + 보통)"

# R13. [#267 높음] 플레이스홀더 필터가 행 단위로 넓다 — 채워진 행의 <보류> 한 칸이 행 전체를 면제,
#      전 행이 그러면 「도입 전」 오판 재발. 필터는 ID 칸(첫 칸)이 통째 <…>일 때만 양식 행이다.
d=$(make_fixture '| FR-1 | prd.md | <보류> | ✅ | M1 | C01 | 1 | — | ✅ 완료 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
add_registries "$d" '| C01 | 첫 | 🔵 |'
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
expect_signal "R13 <보류> 칸이 있어도 완료-무테스트를 잡는다" "$d" "완료인데 테스트가 없다"
d=$(make_fixture '| FR-1 | prd.md | <SC-1> | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |
| FR-2 | prd.md | <SC-2> | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
add_registries "$d"
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
expect_no_signal "R13 부분 placeholder 행을 도입 전으로 오판하지 않는다" "$d" "도입 전"
expect_signal "R13 부분 placeholder 행이 있어도 검사 I 는 돈다" "$d" "사이클 현황 표에 행이 없다"

# R14. [#268 높음] 앞공백 행 — GFM 은 3칸까지 표로 렌더하는데 검사만 못 읽던 것 (양방향)
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf ' | C02 | 들여쓴 유령 | 🔵 |\n' >> "$d/docs/plan/index.md"
expect_signal "R14 앞공백 유령 사이클 행을 잡는다" "$d" "행은 있는데 사이클 문서가 없다"
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf ' | ST-002 | 닫힘 | ✅ |\n' >> "$d/docs/status/STATUS.md"
printf '# ST-002\n' > "$d/docs/plan/archive/stories/ST-002-old.md"
expect_signal "R14 앞공백 잔존 Story 행을 잡는다" "$d" "행이 남아 있다"
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf ' | C01 | 들여쓴 정상 | 🔵 |\n' >> "$d/docs/plan/index.md"
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
expect_no_signal "R14 앞공백 정상 등재를 오탐하지 않는다" "$d" "행이 없다"

# R15. [#269 높음] 정본 매핑표(table_of)의 절단 — 표 안 빈 줄·앞공백 행 아래가 무음 유실되던 것
d=$(make_fixture '| FR-1 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |

| FR-9 | prd.md | — | — | | | 3 | — | ✅ 완료 | 상류 바뀜 |')
expect_signal "R15 표 안 빈 줄 아래 행의 마일스톤 빔을 잡는다" "$d" "마일스톤 배치가 비었다"
expect_signal "R15 표 안 빈 줄 아래 행의 재검토 잔존을 잡는다" "$d" "재검토가 남아 있다"
d=$(make_fixture '| FR-1 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |
 | FR-9 | prd.md | — | — | | | 3 | — | ✅ 완료 | 상류 바뀜 |')
expect_signal "R15 앞공백 매핑표 행도 읽는다" "$d" "마일스톤 배치가 비었다"

# R16. [#270 보통] 레지스트리 구조 이탈은 경고가 아니라 **실패**다 — 열 개명 하나로
#      검사 I 전체가 경고 한 줄(exit 0)로 무력화되면 CI·게이트가 통과시킨다
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '# plan\n\n## 사이클 현황\n\n| 번호 | 이름 | 상태 |\n|---|---|---|\n| C02 | 유령 | 🔵 |\n' > "$d/docs/plan/index.md"
expect_signal "R16 구조 이탈은 실패 등급이다" "$d" "정합성 검사 실패"

# R17. [#271 보통] 장식+뒤 텍스트 ID — [C02](x) 참조 · **ST-002** (메모) 가 판정 제외되던 것
d=$(make_fixture "$I_BASE"); add_registries "$d" '| [C02](docs/x.md) 참조 | 유령 | 🔵 |'
expect_signal "R17 링크+뒤 텍스트 유령 행을 잡는다" "$d" "행은 있는데 사이클 문서가 없다"
d=$(make_fixture "$I_BASE"); add_registries "$d" '' '' '| **ST-002** (닫힘 메모) | 닫힘 | ✅ |'
printf '# ST-002\n' > "$d/docs/plan/archive/stories/ST-002-old.md"
expect_signal "R17 볼드+뒤 텍스트 잔존 Story 행을 잡는다" "$d" "행이 남아 있다"

echo
echo "검사 J — 계획 깊이 (self:plan 계획 문서)"

# self:plan 계획 문서를 깐 fixture.
# $1 = plan.md 본문
# $2 = (선택) 매핑표 2절 데이터 행 — **주면 「도입 후」 fixture**가 된다.
#      안 주면 매핑표가 없어 A~I 는 쉬고 J 만 도는 「/mdm-adopt 직전」 상태다.
#      1회전 K6 이 「J fixture 가 전부 도입 전이라, 도입 후 J 를 꺼도 전 케이스 초록」을 실측했다(#288) —
#      `/mdm-review` 1단계와 CI 가 도는 것은 도입 **후** 경로다.
make_plan() {
  local d="$TMP/fxj" h
  rm -rf "$d"
  mkdir -p "$d/.claude/scripts" "$d/docs/upstream"
  cp "$KIT/.claude/scripts/check-consistency.sh" "$d/.claude/scripts/"
  chmod +x "$d/.claude/scripts/check-consistency.sh"
  printf '%s\n' "$1" > "$d/docs/upstream/plan.md"
  if command -v sha256sum >/dev/null 2>&1; then h=$(sha256sum "$d/docs/upstream/plan.md" | awk '{print $1}')
  else h=$(shasum -a 256 "$d/docs/upstream/plan.md" | awk '{print $1}'); fi
  printf '# 수집 기록\nplan.md\tself:plan\t2026-01-01T00:00:00Z\t%s\n' "$h" > "$d/docs/upstream/manifest.tsv"
  if [ -n "${2:-}" ]; then
    mkdir -p "$d/docs/spec"
    { printf '# source-map\n\n## 2. 요구사항 매핑표\n\n'
      printf '| ID | 출처 | 화면 | 준비 | 마일스톤 | 사이클 | 조건 수 | 테스트 | 상태 | 재검토 |\n'
      printf '|---|---|---|---|---|---|---|---|---|---|\n'
      printf '%s\n' "$2"
      printf '\n## 3. 화면 매핑표\n\n| ID | 이름 | 관련 요구사항 |\n|---|---|---|\n\n'
    } > "$d/docs/spec/source-map.md"
    printf '# interface\n' > "$d/docs/spec/interface.md"
  fi
  printf '%s' "$d"
}

# 같은 계획을 **CRLF 줄끝**으로 다시 깐다 (해시도 그 파일로 다시 기록한다).
# fixture 가 전부 bash heredoc(LF 고정)이라 이 경로를 재는 케이스가 0건이었다 — 1회전 K2·K3 독립 #357.
crlf_plan() { # $1 = make_plan 이 만든 fixture 경로
  local d="$1" h
  python3 - "$d/docs/upstream/plan.md" <<'CPY'
import sys
p = sys.argv[1]
b = open(p, 'rb').read().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
open(p, 'wb').write(b)
CPY
  if command -v sha256sum >/dev/null 2>&1; then h=$(sha256sum "$d/docs/upstream/plan.md" | awk '{print $1}')
  else h=$(shasum -a 256 "$d/docs/upstream/plan.md" | awk '{print $1}'); fi
  printf '# 수집 기록\nplan.md\tself:plan\t2026-01-01T00:00:00Z\t%s\n' "$h" > "$d/docs/upstream/manifest.tsv"
  printf '%s' "$d"
}

# 기대 신호 + **차단 등급 + 종료코드**를 함께 잰다.
# expect_signal 은 메시지만 보므로 bad → caution 강등을 못 잡는다 — 1회전 K6 이
# 「J 의 bad 9곳을 caution 으로 내려도 전 케이스 초록」을 실측했다(#287).
# 「정합성 검사 통과」가 「정합성 검사 통과 (경고 있음)」의 접두인 것이 그 무음의 기계적 원인이다.
expect_fail() { # $1 설명  $2 fixture경로  $3 기대 문자열
  local out rc
  out="$(run "$2")"; rc=$?
  case "$out" in
    *"$3"*) ;;
    *) ng "$1 — 기대 신호가 없다: '$3'"; printf '%s\n' "$out" | sed 's/^/        /'; return ;;
  esac
  case "$out" in
    *"실패  "*) ;;
    *) ng "$1 — 신호는 났으나 **실패 등급이 아니다** (경고로 강등되면 CI·게이트가 통과시킨다)"
       printf '%s\n' "$out" | sed 's/^/        /'; return ;;
  esac
  if [ "$rc" = 1 ]; then ok "$1"; else ng "$1 — 신호는 났으나 rc=$rc 다 (1 이어야 한다)"; fi
}

J_PERM='## 2. 사용자와 권한

| 역할 | 할 수 있는 것 | 할 수 없는 것 | 거부되면 |
|---|---|---|---|
| 관리자 | 전부 | — | — |
| 일반 | 자기 것 조회 | 남의 것 조회 | 숨김 |'

J_SPEC='## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 「가져오기」 누름 | 권한 확인 후 선택기를 연다 | 파일이 선택됨 | 파일 모듈 | — | ✅ |
| FR-1-F1-S2 | — | — | — | 통계 모듈 | FR-1-F1-S1 | — |'

J_OK="# 데모 — 계획

$J_PERM

$J_SPEC"

# J1. 다 채운 계획은 조용하다 (경계값 — 정상 입력에서 울면 검사가 무뎌진다)
d=$(make_plan "$J_OK")
expect_signal "J1 다 채운 계획은 통과한다" "$d" "정합성 검사 통과"
expect_no_signal "J1 다 채운 계획에 오탐이 없다" "$d" "실패"
# 1회전 K2·K6: 옛 J1-b 는 '도입 전' 문자열만 봤는데 그건 J 가 아니라 note 에서 나온다 —
# J 를 통째로 들어내도 통과하는 **공허한 단언**이었다(#305). 도입 전에 J 가 **막는지**를 잰다.
expect_fail "J1-b 도입 전(매핑표 없이)에도 J 가 막는다" \
  "$(make_plan "${J_OK/| 파일 모듈 |/| — |}")" "영향 영역이 비었다"

# J2. 영향 영역이 '—' 면 실패 — 병렬 계산의 입력이라 '해당 없음' 을 답으로 받지 않는다
d=$(make_plan "${J_OK/| 파일 모듈 |/| — |}")
expect_fail "J2 영향 영역 '—' 를 잡는다" "$d" "영향 영역이 비었다"
d=$(make_plan "${J_OK/| 파일 모듈 |/|  |}")
expect_fail "J2 영향 영역 빈 칸을 잡는다" "$d" "영향 영역이 비었다"

# J3. 선행은 빈 칸만 실패다 — '—'(선행 없음)는 정상 답이다
d=$(make_plan "${J_OK/| 파일 모듈 | — | ✅ |/| 파일 모듈 |  | ✅ |}")
expect_fail "J3 선행 빈 칸을 잡는다" "$d" "선행 칸이 비었다"
expect_no_signal "J3 선행 '—' 는 오탐하지 않는다" "$(make_plan "$J_OK")" "선행 칸이 비었다"

# J4. '먼저' 칸이 비면 실패 — 첫 묶음인지 아닌지가 뒤 검사의 분기다
d=$(make_plan "${J_OK/| 파일 모듈 | — | ✅ |/| 파일 모듈 | — |  |}")
expect_fail "J4 '먼저' 빈 칸을 잡는다" "$d" "'먼저' 칸이 비었다"

# J5. '먼저 ✅' 인데 트리거·동작·결과가 비면 실패 — **세 칸을 각각 잰다**
#     (1회전 K6 #300: 옛 J5 는 '동작' 하나만 재서, 나머지 둘을 지워도 초록이었다)
d=$(make_plan "${J_OK/| 권한 확인 후 선택기를 연다 |/| — |}")
expect_fail "J5 먼저 ✅ 인데 동작이 빈 것을 잡는다" "$d" "'동작' 가 비었다"
d=$(make_plan "${J_OK/| 「가져오기」 누름 |/| — |}")
expect_fail "J5 먼저 ✅ 인데 트리거가 빈 것을 잡는다" "$d" "'트리거' 가 비었다"
d=$(make_plan "${J_OK/| 파일이 선택됨 |/| — |}")
expect_fail "J5 먼저 ✅ 인데 결과가 빈 것을 잡는다" "$d" "'결과' 가 비었다"
expect_no_signal "J5 먼저 — 인 행의 빈 트리거·동작·결과는 오탐하지 않는다" "$(make_plan "$J_OK")" "가 비었다"

# J6. 사양 표가 기능 소제목(####) 아래에 없으면 실패 — 기능 층이 통째로 빠진 것이다
#     (`${var/#…}` 는 앞 앵커 치환이라 '#' 로 시작하는 패턴을 못 쓴다 — 본문을 직접 깐다)
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |")
expect_fail "J6 기능 소제목 없는 사양 표를 잡는다" "$d" "기능 소제목"

# J7. 필수 열을 개명하면 조용히 꺼지지 않고 '열이 없다'로 붉어진다 — **다섯 열 각각**
#     (1회전 K6 #300: 옛 J7 은 '영향 영역' 하나만 재서, 나머지를 목록에서 지워도 초록이었다)
J_HDR='| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |'
for col in 트리거 동작 결과 선행 먼저; do
  d=$(make_plan "${J_OK/$J_HDR/${J_HDR/| $col |/| 딴이름 |}}")
  expect_fail "J7 '$col' 열 개명을 잡는다" "$d" "'$col' 열이 없다"
done

# J8. 앵커 열을 개명하면 표 자체를 못 찾는다 → 추출 0 건은 통과가 아니라 실패다.
#     앵커는 '사양'·'영향 영역' **둘 다**다 — 한 열만 앵커로 쓰면 계획의 다른 표(낱말 정의·색인)가
#     걸려 정상 문서가 붉어진다(1회전 K1 #293). 어느 쪽을 개명해도 fail-closed 여야 한다.
d=$(make_plan "${J_OK/| 사양 | 트리거 |/| 스펙 | 트리거 |}")
expect_fail "J8 앵커 '사양' 개명은 '한 건도 찾지 못했다'로 붉어진다" "$d" "사양 행을 한 건도 찾지 못했다"
d=$(make_plan "${J_OK/| 영향 영역 | 선행 |/| 영역 | 선행 |}")
expect_fail "J8 앵커 '영향 영역' 개명도 fail-closed 다" "$d" "사양 행을 한 건도 찾지 못했다"

# J9. 양식 행만 남은 계획 — 채운 척이 통과하지 않는다
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: <이름>

#### FR-1-F1: <기능>

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| <FR-1-F1-S1> | <무엇이> | <무엇을> | <무엇이> | <어디> | <—> | <✅> |")
expect_fail "J9 양식 행만 있는 계획을 잡는다" "$d" "사양 행을 한 건도 찾지 못했다"

# J9-b. [#280] 양식 행 면제는 **앵커 칸(사양) 기준**이지 물리적 1번 칸이 아니다.
#       파일 머리가 「열 위치도 고정하지 않는다」고 약속하는데 필터만 위치를 고정하면,
#       열 순서를 바꾸는 것으로 아무 칸이나 면제 열쇠가 된다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 기능 | 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|---|
| <미정> | FR-1-F1-S1 | 누름 | 연다 | 열림 |  |  |  |")
expect_fail "J9-b 1번 칸이 <…>여도 앵커 칸이 실값이면 면제되지 않는다" "$d" "영향 영역이 비었다"

# J9-c. [#280] 채워진 실물 행의 앵커 칸만 <…>인 경우 — 이것은 **양식 행이 맞다**(면제).
#       #267 이 「첫 칸 한정」으로 좁힌 규칙 그대로다. 면제된 결과 사양 행이 0건이면 그때 잡힌다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| <미정> | 취소 누름 | 닫는다 | 닫힘 |  |  |  |")
expect_fail "J9-c 앵커 칸이 양식이면 면제되고, 남은 행이 0 건이라 잡힌다" "$d" "사양 행을 한 건도 찾지 못했다"

# J10. 권한 표가 없으면 실패 — 누가 무엇을 할 수 있나는 요구사항 그 자체다
d=$(make_plan "# 데모 — 계획

$J_SPEC")
expect_fail "J10 권한 표가 없는 계획을 잡는다" "$d" "권한 표를 찾지 못했다"

# J11. '거부되면' 칸이 비면 실패 — 거부 경로가 없으면 화면마다 다르게 구현된다
d=$(make_plan "${J_OK/| 자기 것 조회 | 남의 것 조회 | 숨김 |/| 자기 것 조회 | 남의 것 조회 |  |}")
expect_fail "J11 '거부되면' 빈 칸을 잡는다" "$d" "'거부되면' 칸이 비었다"

# J12. 권한 표의 열 개명 — 앵커('역할'·'거부되면')는 fail-closed, 필수 열은 '열이 없다'
d=$(make_plan "${J_OK/| 역할 | 할 수 있는 것 | 할 수 없는 것 | 거부되면 |/| 역할 | 할 수 있는 것 | 할 수 없는 것 | 거부 |}")
expect_fail "J12 앵커 '거부되면' 개명은 fail-closed 다" "$d" "권한 표를 찾지 못했다"
d=$(make_plan "${J_OK/| 역할 | 할 수 있는 것 |/| 역할 | 할 수 있는 것들 |}")
expect_fail "J12 '할 수 있는 것' 열 개명을 잡는다" "$d" "'할 수 있는 것' 열이 없다"

# J13. 출처가 self:plan 이 아니면 J 를 걸지 않는다 — 외부 스냅샷은 읽기 전용이고 형식이 그쪽 것이다.
#      조용히 꺼지지 않고 「건너뛴다」를 알린다 (B·H 와 같은 규율).
d=$(make_plan "# 계획

내용 없음")
sed 's/self:plan/repo:docs\/PRD.md/' "$d/docs/upstream/manifest.tsv" > "$d/m" && mv "$d/m" "$d/docs/upstream/manifest.tsv"
expect_signal "J13 외부 상류면 건너뛴다고 알린다" "$d" "계획 깊이 검사(J)를 건너뛴다"
expect_no_signal "J13 외부 상류에 J 를 걸지 않는다" "$d" "한 건도 찾지 못했다"

# J14. 코드펜스 안의 예시 표는 읽지 않는다 (검사 I 의 R7 과 같은 함정)
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

예시:

\`\`\`
| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| S-X |  |  |  |  |  |  |
\`\`\`

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |")
expect_no_signal "J14 코드펜스 안 예시 표를 오탐하지 않는다" "$d" "S-X"
expect_signal "J14 코드펜스를 지나 진짜 표를 읽는다" "$d" "정합성 검사 통과"

# ── 1회전 적발분 (치명 1 · 높음 5 — 전부 반증 확정) ──────────────────────

# J15. [#279 치명] 표 안 빈 줄에서 절단하면 그 아래 행 **전부**가 무음으로 빠진다.
#      이 저장소가 같은 결함을 이미 두 번 확정했다 — table_of(#269) · reg_table(1회전).
#      table_of 는 빈 줄을 절단으로 안 보는데(`l == "" { next }`) plan_rows 만 hdr 을 리셋했다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |

| FR-1-F1-S2 |  |  |  |  |  | — |")
expect_fail "J15 표 안 빈 줄 아래의 사양 행을 읽는다" "$d" "영향 영역이 비었다"

# J15-b. 권한 표에서도 같다 — 빈 줄 아래 행의 '거부되면' 빈 칸이 무음이었다
d=$(make_plan "# 데모 — 계획

## 2. 사용자와 권한

| 역할 | 할 수 있는 것 | 할 수 없는 것 | 거부되면 |
|---|---|---|---|
| 관리자 | 전부 | — | — |

| 일반 | 자기 것 조회 | 남의 것 조회 |  |

$J_SPEC")
expect_fail "J15-b 표 안 빈 줄 아래의 권한 행도 읽는다" "$d" "'거부되면' 칸이 비었다"

# J16. [#281] `~~~` 펜스와 4칸 들여쓴 코드블록 안의 예시 표를 진짜 표로 세면,
#      기능·사양이 **하나도 없는 계획**이 예시만으로 통과한다.
#      P3 골격 자체가 ```markdown 펜스라, 계획 안에서 펜스를 품은 예시를 보이려면 `~~~` 가 관용 답이다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

아직 기능·사양을 안 내려갔다. 아래는 양식 예시일 뿐이다.

~~~markdown
#### 예시-F1: 예시 기능

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| 예시-S1 | 누름 | 연다 | 열림 | 예시 모듈 | — | ✅ |
~~~")
expect_fail "J16 ~~~ 펜스 안 예시를 사양으로 세지 않는다" "$d" "사양 행을 한 건도 찾지 못했다"

d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

예시(들여쓴 코드블록):

    #### 예시-F1: 예시 기능

    | 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
    |---|---|---|---|---|---|---|
    | 예시-S1 | 누름 | 연다 | 열림 | 예시 모듈 | — | ✅ |")
expect_fail "J16-b 4칸 들여쓴 코드블록도 사양으로 세지 않는다" "$d" "사양 행을 한 건도 찾지 못했다"

# J16-c. 반대 방향 오탐 — 멀쩡한 계획 옆의 `~~~` 예시가 실패를 만들면 안 된다
d=$(make_plan "$J_OK

## 부록

~~~markdown
| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| 이렇게-쓰지-마라 |  |  |  |  |  |  |
~~~")
expect_no_signal "J16-c ~~~ 예시가 멀쩡한 계획을 오탐하지 않는다" "$d" "이렇게-쓰지-마라"
expect_signal "J16-c 그 계획은 통과한다" "$d" "정합성 검사 통과"

# J17. [#282] manifest 형식 이탈에서 J 가 통째로 꺼지면 안 된다.
#      더 나쁜 것은 같은 실행이 「건너뛴다」와 「J 만 돌았다」를 동시에 내는 **거짓 통과 주장**이었다.
J_SHALLOW="# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

산문만 있고 기능·사양이 없다."
mf() { printf '%s' "$TMP/fxj/docs/upstream/manifest.tsv"; }
plan_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$TMP/fxj/docs/upstream/plan.md" | awk '{print $1}'
  else shasum -a 256 "$TMP/fxj/docs/upstream/plan.md" | awk '{print $1}'; fi
}
d=$(make_plan "$J_SHALLOW"); printf '# 수집 기록\nplan.md\tself:plan\t2026-01-01T00:00:00Z\t%s' "$(plan_sha)" > "$(mf)"
expect_fail "J17 후행 개행 없는 manifest 마지막 줄도 읽는다" "$d" "사양 행을 한 건도 찾지 못했다"

d=$(make_plan "$J_SHALLOW"); printf '# 수집 기록\nplan.md \tself:plan\t2026-01-01T00:00:00Z\t%s\n' "$(plan_sha)" > "$(mf)"
expect_fail "J17-b 파일명 뒤 공백이 있어도 J 가 돈다" "$d" "사양 행을 한 건도 찾지 못했다"

d=$(make_plan "$J_SHALLOW"); printf '# 수집 기록\nplan.md self:plan 2026-01-01T00:00:00Z %s\n' "$(plan_sha)" > "$(mf)"
expect_fail "J17-c 탭이 아닌 구분자를 조용히 넘기지 않는다" "$d" "탭 4열"

# J17-f. [#324] 「탭 4열」 가드가 실제로는 「탭 1개 이상」이었다 — 첫 구분자만 탭이면
#        jsrc 가 통째로 잘못 잡혀 J 가 조용히 꺼지고 「상류가 외부 도구다」 + rc=0 이 된다.
#        J17-c 는 **탭이 하나도 없는** 줄만 재서 이 잔여를 못 잡았다 (2회전 K2·K3·K4 3축 독립).
d=$(make_plan "$J_SHALLOW"); printf '# 수집 기록\nplan.md\tself:plan 2026-01-01T00:00:00Z %s\n' "$(plan_sha)" > "$(mf)"
expect_fail "J17-f 탭이 1개뿐인 줄도 잡는다 (가드가 '탭 1개 이상'이 아니다)" "$d" "탭 4열"
d=$(make_plan "$J_SHALLOW"); printf '# 수집 기록\nplan.md\tself:plan\t2026-01-01T00:00:00Z\t%s\t군더더기\n' "$(plan_sha)" > "$(mf)"
expect_fail "J17-f2 탭이 4개 이상인 줄도 잡는다 (열이 남아도 형식 이탈이다)" "$d" "탭 4열"

d=$(make_plan "$J_SHALLOW"); rm -f "$d/docs/upstream/plan.md"
printf '# 수집 기록\nplan.md\tself:plan\t2026-01-01T00:00:00Z\tdeadbeef\n' > "$(mf)"
expect_fail "J17-d self:plan 행은 있는데 파일이 없으면 잡는다 (도입 전엔 검사 A 가 안 돈다)" "$d" "수집 기록에 있는데 파일이 없다"

# J17-e. 「건너뛴다」와 「J 만 돌았다」가 같은 실행에서 함께 나오면 안 된다 (#303)
d=$(make_plan "$J_OK")
sed 's/self:plan/repo:docs\/PRD.md/' "$(mf)" > "$d/m" && mv "$d/m" "$(mf)"
expect_no_signal "J17-e 건너뛴 실행이 「J 만 돌았다」고 말하지 않는다" "$d" "계획 깊이 검사 J 만 돌았다"

# J18. [#283] 「모든 요구사항이 기능으로, 모든 기능이 사양으로」의 **전칭**을 실제로 센다.
#      옛 J 는 파일 전체에 사양 행이 하나만 있어도 통과했다 — DoD 가 그것을 (검사 J)로 귀속했다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |

### FR-2: 통계 보기

산문만 있고 기능이 없다.")
expect_fail "J18 기능이 없는 요구사항을 잡는다" "$d" "기능(####)이 없다"

d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |

#### FR-1-F2: 파일 검증

산문만 있고 사양 표가 없다.")
expect_fail "J18-b 사양 표가 없는 기능을 잡는다" "$d" "사양 표가 없다"

# J19. [#294] 셀 안 escape 파이프(\\|)가 열을 밀면, 빈 칸이 면제되거나 엉뚱한 칸을 읽어 오보한다.
#      트리거·동작·결과 같은 자유 산문 열에 처음 적용한 것이 J 다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | CSV \\| TSV 를 읽는다 | 열림 | — |  | ✅ |")
expect_fail "J19 escape 파이프가 있어도 영향 영역을 제 자리에서 읽는다" "$d" "영향 영역이 비었다"

# J20. [#288] **도입 후**(매핑표 존재) 경로에서도 J 가 돈다.
#      `/mdm-review` 1단계와 CI 가 도는 것은 이쪽이다 — 옛 fixture 는 21개가 전부 도입 전이었다.
J_ADOPTED='| FR-1 | plan.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |'
d=$(make_plan "${J_OK/| 파일 모듈 |/| — |}" "$J_ADOPTED")
expect_fail "J20 도입 후에도 J 가 막는다" "$d" "영향 영역이 비었다"
expect_no_signal "J20 도입 후 fixture 는 '도입 전' 경로가 아니다" "$d" "도입 전"
d=$(make_plan "$J_OK" "$J_ADOPTED")
expect_signal "J20-b 도입 후 정상 계획은 통과한다" "$d" "정합성 검사 통과"

# J21. [#300] self:plan 문서가 **둘 이상**이면 둘 다 본다 (마지막 하나만 보는 회귀를 막는다)
d=$(make_plan "$J_OK")
printf '%s\n' "$J_SHALLOW" > "$d/docs/upstream/plan2.md"
if command -v sha256sum >/dev/null 2>&1; then h2=$(sha256sum "$d/docs/upstream/plan2.md" | awk '{print $1}')
else h2=$(shasum -a 256 "$d/docs/upstream/plan2.md" | awk '{print $1}'); fi
printf 'plan2.md\tself:plan\t2026-01-01T00:00:00Z\t%s\n' "$h2" >> "$(mf)"
expect_fail "J21 self:plan 문서가 둘이면 둘 다 본다" "$d" "plan2.md"

# J22. [#285] 전부 빈 칸인 행은 구분줄이 아니다 — 검사가 잡으려는 「가장 빈 행」이다
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |
|  |  |  |  |  |  |  |")
expect_fail "J22 전부 빈 칸인 행을 구분줄로 오인하지 않는다" "$d" "영향 영역이 비었다"

# ── 2회전 적발분 (확정 높음 6 — #320~#325) ──────────────────────────────

# J23. [#320 높음] **전칭 검사의 사정권이 자기 목표를 무력화하던 것.**
#      옛 판은 요구사항 절을 「사양 행이 **발견된** 절」로 잡았다 — 그래서 사양 표가 아예 없는 절,
#      곧 계획이 요구사항에서 멈춘 **바로 그 절**이 구조적으로 사정권 밖이었다. 순환이다.
#      요구사항을 두 절로 나누고 둘째가 산문뿐이면 도입 전·후 **모두 rc=0** 이었다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 핵심 요구사항

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |

## 5. 부가 요구사항

### FR-2: 통계 보기

산문만 있고 기능이 없다.")
expect_fail "J23 사양 표가 없는 둘째 요구사항 절도 사정권 안이다" "$d" "기능(####)이 없다"

# J23-b. 그 절에 요구사항(###)조차 없으면 — 절 자체가 산문뿐인 경우다.
#        옛 판은 close_req 가 안 걸려 **완전 무음**이었다 (파일 어딘가에 사양 행이 있으면 백스톱도 안 돈다).
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 핵심 요구사항

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |

## 5. 부가 요구사항

아직 안 정했다.")
expect_fail "J23-b 요구사항(###)이 하나도 없는 요구사항 절을 잡는다" "$d" "요구사항(###)이 없다"

# J23-c. 반대 방향 오탐 — 요구사항 절이 **아닌** 절의 ###/#### 는 계층으로 읽지 않는다.
#        사정권을 절 제목의 낱말로 잡는 대가가 이것이다. 여기서 울면 정상 계획이 붉어진다.
d=$(make_plan "$J_OK

## 부록

### 참고 자료

산문만 있다.")
expect_no_signal "J23-c 요구사항 절이 아닌 절의 ### 를 요구사항으로 읽지 않는다" "$d" "기능(####)이 없다"
expect_signal "J23-c2 그 계획은 통과한다" "$d" "정합성 검사 통과"

# J24. [#322 높음] **레벨 1–2 ATX 제목이 하나도 없으면 전칭 셋이 통째로 무음이었다.**
#      in_req_sec 이 jlv<=2 H 행 없이는 절대 안 켜졌다. setext 제목은 그 한 사례일 뿐이다.
d=$(make_plan "데모 — 계획
===========

사용자와 권한
------------

| 역할 | 할 수 있는 것 | 할 수 없는 것 | 거부되면 |
|---|---|---|---|
| 관리자 | 전부 | — | — |

요구사항
--------

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |

### FR-2: 통계 보기

산문만 있고 기능이 없다.")
expect_fail "J24 setext 제목뿐인 계획을 조용히 통과시키지 않는다" "$d" "요구사항 절을 찾지 못했다"

# J24-b. 최상위가 ### 인 ATX 계획도 같다 — setext 만의 문제가 아니었다.
d=$(make_plan "### FR-1: 파일 가져오기

$J_PERM

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |

### FR-2: 통계 보기

산문만 있고 기능이 없다.")
expect_fail "J24-b 최상위가 ### 인 계획도 잡는다" "$d" "요구사항 절을 찾지 못했다"

# J25. [#321 높음] **「추출 0 건을 통과로 세지 않는다」가 정확히 0 건일 때 안 떴다.**
#      printf '%s\n' "$jscan" 이 빈 스캔에서 **빈 줄 하나**를 내고 read 가 성공해 n_spec=1 이 됐다.
#      그 약속을 적어 놓은 바로 그 자리에서 어긴 것이다 (루트 CLAUDE.md 셸 함정 3번).
#      방아쇠는 「ATX 제목이 하나도 없다 + 권한 표는 있다」다 — 권한 표 경로는 grep 이 앞에 있어 무사했다.
d=$(make_plan "| 역할 | 할 수 있는 것 | 할 수 없는 것 | 거부되면 |
|---|---|---|---|
| 관리자 | 전부 | — | — |")
expect_fail "J25 스캔이 정확히 0 건이어도 '한 건도 찾지 못했다'가 뜬다" "$d" "사양 행을 한 건도 찾지 못했다"

# J26. [#323 높음] **「도입 전에도 J 가 막는다」의 실제 경로에 fixture 가 0 건이었다.**
#      조기 종료는 둘이다 — ① 매핑표 파일 없음 ② 파일은 있고 **행이 없음**(양식 행뿐).
#      키트 배포본 source-map.md 는 양식 행뿐이라 `/mdm-plan` 직후의 실제 경로는 ②다.
#      2회전 반증이 경로 계수기를 심어 실측했다: PATH1 49회 · PATH_ADOPTED 62회 · **PATH2 0회.**
J_TEMPLATE_ROW='| <R-AOTSCK> | <prd.md §3.1> | <SC-002> | <✅ ST-003> | <M1> | <C01> | <5> | <test_ok> | ⬜ 대기 | — |'
d=$(make_plan "${J_OK/| 파일 모듈 |/| — |}" "$J_TEMPLATE_ROW")
expect_signal "J26 매핑표가 양식 행뿐이면 조기 종료 ②로 간다" "$d" "양식만 있음"
expect_fail "J26-b 그 경로(도입 전 ②)에서도 J 가 막는다" "$d" "영향 영역이 비었다"

# J27. [#342 높음] **`<…>` 양식 텍스트가 「채워짐」으로 통과하던 것.**
#      칸 판정이 `''|'—'|'-'` **빈 칸 셋뿐**이라, 골격에서 **앵커 칸(사양·역할)만 실값으로** 바꾸면
#      나머지가 골격 글자 그대로여도 J 가 전부 통과했다. 더 나쁜 것은 골격이 배포하는 `<✅ / —>` 가
#      `*✅*` 에 매치돼 **가장 엄한 하위 검사를 켜 놓고**, 같은 골격의 `<무엇이 시작시키나>` 가
#      그것을 통과시킨 것이다. 반증이 **도입 후 경로에서도** 뚫리는 것을 실측했다.
#      골격(docs/guides/plan.md P3)의 글자를 그대로 쓴다 — 이것이 기본 실패 모드다.
J_SKEL_ROW='| FR-1-F1-S1 | <무엇이 시작시키나> | <시스템이 무엇을 하나 — 순서대로> | <끝나면 무엇이 달라져 있나> | <손댈 모듈·경계> | <먼저 되어 있어야 할 사양 ID, 없으면 —> | <✅ / —> |'
J_SKEL="# 데모 — 계획

## 2. 사용자와 권한

| 역할 | 할 수 있는 것 | 할 수 없는 것 | 거부되면 |
|---|---|---|---|
| 관리자 | <무엇을 할 수 있나 — 능력으로> | <경계> | <숨김 / 안내 후 차단 / 오류> |

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
$J_SKEL_ROW"
d=$(make_plan "$J_SKEL")
expect_fail "J27 앵커만 채운 골격의 '영향 영역'을 채워짐으로 세지 않는다" "$d" "영향 영역이 비었다"
expect_fail "J27-b 같은 행의 '선행'도 잡는다" "$d" "선행 칸이 비었다"
expect_fail "J27-c '<✅ / —>' 를 '먼저' 답으로 받지 않는다" "$d" "'먼저' 칸이 비었다"
expect_fail "J27-d 권한 표의 '거부되면' 양식도 잡는다" "$d" "'거부되면' 칸이 비었다"

# J27-e. **도입 후 경로에서도** 뚫렸다 — /mdm-review 1단계와 CI 가 도는 것은 이쪽이다.
d=$(make_plan "$J_SKEL" "$J_ADOPTED")
expect_fail "J27-e 도입 후 경로에서도 양식 칸을 잡는다" "$d" "영향 영역이 비었다"
expect_no_signal "J27-e2 도입 후 fixture 는 '도입 전' 경로가 아니다" "$d" "도입 전"

# J27-f. 반대 방향 오탐 — `<` 나 `>` 를 담은 **실제 값**을 양식으로 오인하면 안 된다.
#        규칙은 plan_scan 의 양식 행 판정과 같다: **통째로 <…> 이고 안에 '>' 가 없을 때만** 양식이다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | <script> 태그 입력 | a > b 로 정렬한다 | <대기> → <완료> | 파서 모듈 | — | ✅ |")
expect_no_signal "J27-f '<script>' 처럼 뒤에 글이 붙은 값을 양식으로 오인하지 않는다" "$d" "트리거' 가 비었다"
expect_no_signal "J27-f2 '<대기> → <완료>'(안에 '>' 있음)도 실값이다" "$d" "결과' 가 비었다"
expect_signal "J27-f3 그 계획은 통과한다" "$d" "정합성 검사 통과"

# J28. [#357 높음 — K2·K3 독립, 반증이 치명→높음 강등 후 확정] **구분줄이 데이터 행으로 소비되던 것.**
#      필터가 `[[:space:]]` 가 아니라 리터럴 `[|: -]` 라, 구분줄 끝에 **보이지 않는 문자 하나**(CR·탭)만
#      붙으면 구분줄이 데이터 행으로 세어진다. 그 행의 칸은 전부 `---` 이라 `''`·`—`·`-` 어디에도
#      안 걸려 칸 검사를 전부 통과하고, **`n_spec`·`feat_spec`·`n_role` 백스톱 셋을 동시에 무력화**한다.
#      같은 파일의 `data_rows` 는 `[[:space:]:|-]` 라 이 구멍이 없었다 — **새 코드가 기존 필터에서 후퇴했다.**
#      반증 실측: J 의 bad 14 자리 중 무음이 되는 것은 3 자리(전칭·존재 검사)라 「통째」는 아니다.
d=$(crlf_plan "$(make_plan "$J_SKEL")")
expect_fail "J28 CRLF 계획에서도 양식 칸을 잡는다" "$d" "영향 영역이 비었다"

# J28-b. 골격 그대로(전 칸 <양식>)인 계획 — LF 면 실패 3건인데 CRLF 면 rc=0 이던 자리
J_TMPL_ONLY="# 데모 — 계획

## 2. 사용자와 권한

| 역할 | 할 수 있는 것 | 할 수 없는 것 | 거부되면 |
|---|---|---|---|
| <관리자> | <무엇을 할 수 있나> | <경계> | <숨김 / 안내 후 차단 / 오류> |

## 4. 요구사항 → 기능 → 사양

### FR-1: <짧은 능력 이름>

#### FR-1-F1: <기능 이름>

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| <FR-1-F1-S1> | <무엇이 시작시키나> | <시스템이 무엇을 하나> | <끝나면 무엇이> | <손댈 모듈> | <없으면 —> | <✅ / —> |"
expect_fail "J28-b LF 골격 그대로는 막힌다 (대조군)" "$(make_plan "$J_TMPL_ONLY")" "사양 행을 한 건도 찾지 못했다"
expect_fail "J28-b2 CRLF 골격 그대로도 막힌다" "$(crlf_plan "$(make_plan "$J_TMPL_ONLY")")" "사양 행을 한 건도 찾지 못했다"
expect_fail "J28-b3 CRLF 에서 권한 표 백스톱도 산다" "$(crlf_plan "$(make_plan "$J_TMPL_ONLY")")" "권한 표를 찾지 못했다"

# J28-c. **LF + 구분줄 끝 탭 1개** — 같은 뿌리다 (CR 만 막으면 반만 닫힌다)
d=$(make_plan "${J_TMPL_ONLY/|---|---|---|---|---|---|---|/|---|---|---|---|---|---|---|	}")
expect_fail "J28-c 구분줄 끝 탭 1개도 구분줄로 본다" "$d" "사양 행을 한 건도 찾지 못했다"

# J28-d. CRLF 에서 **표 안 빈 줄** 아래 행이 유실되지 않는다 — #279(치명)의 CRLF 판.
#        CRLF 빈 줄은 "\r" 이라 `[ -n "$line" ]` 이 참이 되어 산문으로 읽히고 표가 절단됐다.
d=$(crlf_plan "$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |

| FR-1-F1-S2 |  |  |  |  |  | — |")")
expect_fail "J28-d CRLF 에서도 표 안 빈 줄 아래 행을 읽는다 (#279 의 CRLF 판)" "$d" "영향 영역이 비었다"

# J28-e. 반대 방향 오탐 — 정상 계획을 CRLF 로 바꿔도 조용해야 한다
d=$(crlf_plan "$(make_plan "$J_OK")")
expect_signal "J28-e CRLF 정상 계획은 통과한다" "$d" "정합성 검사 통과"
expect_no_signal "J28-e2 CRLF 정상 계획에 오탐이 없다" "$d" "실패"

# J29. [#358 높음 — K2, 반증 확정] **HTML 주석 안의 표를 실제 내용으로 세던 것.**
#      펜스(```·~~~)와 4칸 들여쓰기는 막으면서 **같은 부류인 <!-- -->** 는 안 막았다.
#      결정적: 유령 행이 `n_spec`·`close_feat`·`n_role` 을 채워, **#320·#327 두 강등이 근거로 삼은
#      백스톱을 전부 무력화**한다. 양방향으로 재현됐다 — 무음 통과와 역방향 오탐 둘 다.
d=$(make_plan "# 데모 — 계획

## 2. 사용자와 권한

아직 역할을 안 정했다.

<!--
| 역할 | 할 수 있는 것 | 할 수 없는 것 | 거부되면 |
|---|---|---|---|
| 관리자 | 전부 | — | — |
-->

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

<!-- 나중에 채운다
#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| S-COMMENT | 누름 | 연다 | 열림 | 파일 모듈 | — | — |
-->")
expect_fail "J29 주석 안 사양 표를 실제 내용으로 세지 않는다" "$d" "사양 행을 한 건도 찾지 못했다"
expect_fail "J29-b 주석 안 권한 표도 세지 않는다" "$d" "권한 표를 찾지 못했다"
expect_no_signal "J29-c 주석 안 행을 사양 ID 로 인용하지 않는다" "$d" "S-COMMENT"

# J29-d. 역방향 오탐 — 멀쩡한 계획 옆의 주석 초안 표가 실패를 만들면 안 된다
d=$(make_plan "$J_OK

## 부록

<!--
| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| 초안-S1 |  |  |  |  |  |  |
-->")
expect_no_signal "J29-d 주석 안 초안 표가 멀쩡한 계획을 오탐하지 않는다" "$d" "초안-S1"
expect_signal "J29-d2 그 계획은 통과한다" "$d" "정합성 검사 통과"

# J29-e. 한 줄 주석과 **줄 중간에서 닫히는** 주석도 처리한다
d=$(make_plan "$J_OK

<!-- 한 줄 주석 --> 뒤에 산문")
expect_signal "J29-e 한 줄 주석은 계획을 오탐하지 않는다" "$d" "정합성 검사 통과"

# J30. [#359 높음 — K2, 반증 확정] **manifest 가 없거나 self:plan 행이 없을 때 「상류가 외부 도구다」라고
#      거짓 이유를 말하며 J 가 조용히 꺼지던 것.** 배포본 키트가 **정확히 그 상태**다 —
#      docs/upstream/plan.md 가 물리적으로 있는데 「self:plan 계획 문서도 없다」고 말했다.
#      키트 양식 자신이 *"외부에서 계획을 받아 온 프로젝트라면 이 파일은 지운다"* 라고 그 상태를 금한다.
d=$(make_plan "$J_OK"); rm -f "$d/docs/upstream/manifest.tsv"
expect_fail "J30 스냅샷은 있는데 수집 기록이 없으면 도입 전에도 잡는다" "$d" "수집 기록이 없다"

d=$(make_plan "$J_OK"); printf '# 수집 기록\n' > "$(mf)"
expect_signal "J30-b plan.md 는 있는데 self:plan 행이 없으면 그 사실을 말한다" "$d" "self:plan 으로 기록되지 않았다"
expect_no_signal "J30-b2 그때 「상류가 외부 도구다」라고 말하지 않는다" "$d" "상류가 외부 도구다"

d=$(make_plan "$J_OK"); rm -f "$d/docs/upstream/plan.md"
printf '# 수집 기록\nprd.md\trepo:docs/PRD.md\t2026-01-01T00:00:00Z\tdeadbeef\n' > "$(mf)"
printf '# PRD\n' > "$d/docs/upstream/prd.md"
expect_signal "J30-c 진짜로 외부 상류일 때만 「상류가 외부 도구다」라고 말한다" "$d" "상류가 외부 도구다"

# J31. [#360 높음 — K3, 반증 확정] **「탭 개수 == 3」 가드가 빈 칸을 못 잡는다.**
#      가드는 탭을 세지만 뒤의 `IFS="$TAB" read` 가 TAB 을 **IFS 공백류**로 다뤄 연속 탭을 접고
#      선행 탭을 버린다. 그래서 **1열·2열이 비면** jsrc 가 밀려 self:plan 이 아니게 되고,
#      #324 가 「닫힘」이라 적은 문구가 **글자 그대로** 재현된다 —
#      「jsrc 가 통째로 잘못 잡혀 J 가 조용히 꺼지고 「상류가 외부 도구다」 + rc=0」.
#      반증 실측: bash 3.2·sh·dash·ksh·zsh **전부 동일**. J17-f 계열은 탭 **개수**만 잰다.
#      **#359 와 같은 출구를 공유한다** — 따로 고치면 한쪽이 다른 쪽을 무음으로 되돌린다(반증 경고).
d=$(make_plan "$J_SHALLOW"); printf '# 수집 기록\nplan.md\t\t2026-01-01T00:00:00Z\t%s\n' "$(plan_sha)" > "$(mf)"
expect_fail "J31 출처 칸이 빈 manifest 줄을 잡는다 (탭은 3개라 개수 가드를 통과한다)" "$d" "빈 칸이 있다"
expect_no_signal "J31-a2 그때 「상류가 외부 도구다」라고 말하지 않는다" "$d" "상류가 외부 도구다"

d=$(make_plan "$J_SHALLOW"); printf '# 수집 기록\n\tself:plan\t2026-01-01T00:00:00Z\t%s\n' "$(plan_sha)" > "$(mf)"
expect_fail "J31-b 파일명 칸이 빈 줄도 잡는다" "$d" "빈 칸이 있다"

d=$(make_plan "$J_SHALLOW"); printf '# 수집 기록\nplan.md\tself:plan\t\t%s\n' "$(plan_sha)" > "$(mf)"
expect_fail "J31-c 수집시각 칸이 빈 줄도 잡는다 (J 는 계속 돌지만 형식 이탈은 형식 이탈이다)" "$d" "빈 칸이 있다"

d=$(make_plan "$J_SHALLOW"); printf '# 수집 기록\nplan.md\tself:plan\t2026-01-01T00:00:00Z\t\n' > "$(mf)"
expect_fail "J31-d sha 칸이 빈 줄도 잡는다" "$d" "빈 칸이 있다"

# J31-e. 반대 방향 오탐 — 4칸이 다 찬 정상 줄은 조용해야 한다 (경계값)
expect_no_signal "J31-e 정상 manifest 줄을 오탐하지 않는다" "$(make_plan "$J_OK")" "빈 칸이 있다"

# J32. [#362 — K6] **`plan_scan` 앵커 칸 양식 판정의 「내부 `>` 가드」에 fixture 가 없었다.**
#      `is_ph`(칸 단위) 쪽은 J27-f 계열이 재는데, `plan_scan`(앵커 칸) 쪽은 **두 자리가 갈려** 안 재고 있었다.
#      뮤테이션 M12(`'<'*'>') continue ;;` — 내부 `>` 가드 제거)로 전 케이스가 초록이었다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| FR-1-F1-S1 | 누름 | 연다 | 열림 | 파일 모듈 | — | ✅ |
| <대기> → <완료> | 전이 | 상태를 바꾼다 | 완료됨 |  | — | — |")
expect_fail "J32 앵커 칸이 '<대기> → <완료>'(안에 '>' 있음)면 실값이라 계속 검사한다" "$d" "영향 영역이 비었다"

# J32-b. [#363 — K6] 「**닫는** 꺾쇠」 요구에도 fixture 가 없었다 — 두 자리(`is_ph`·`plan_scan`) 모두.
#        `<미정`(여는 꺾쇠로 시작하고 '>' 가 아예 없는 실값)이 양식으로 오인되면 안 된다.
d=$(make_plan "# 데모 — 계획

$J_PERM

## 4. 요구사항 → 기능 → 사양

### FR-1: 파일 가져오기

#### FR-1-F1: 파일 선택

| 사양 | 트리거 | 동작 | 결과 | 영향 영역 | 선행 | 먼저 |
|---|---|---|---|---|---|---|
| <미정 | 누름 | 연다 | 열림 | <미정 | — | — |")
expect_signal "J32-b '<미정'(닫는 꺾쇠 없음)은 실값이라 통과한다" "$d" "정합성 검사 통과"
expect_no_signal "J32-b2 그것을 양식으로 보고 '한 건도 못 찾았다'로 가지 않는다" "$d" "한 건도 찾지 못했다"
expect_no_signal "J32-b3 그것을 빈 칸으로 보지도 않는다" "$d" "영향 영역이 비었다"

# J33. [#364 — K6] #320 이 가이드에 적은 **대가**에 fixture 가 없었다 —
#      「다른 절 제목에는 「요구사항」을 쓰지 않는다. 쓰면 그 절의 ### 이 요구사항으로 읽혀 붉어진다」.
#      J23-c 는 낱말이 **없는** 절만 잰다. 약속을 적었으면 그 약속이 실제로 그렇게 도는지 못박는다.
d=$(make_plan "$J_OK

## 부록 A. 요구사항 이력

2026-01-01 최초 작성.")
expect_fail "J33 「요구사항」이 든 다른 절 제목은 실제로 붉어진다 (가이드가 적은 대가)" "$d" "요구사항(###)이 없다"

# 뮤테이션 자기검증 — 검사기에서 H 블록을 들어내면 위 fixture 들이 반드시 깨져야 한다.
echo
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

# 준비도 블록도 같은 방식으로 못박는다 — 이것이 없으면 위 8 개 fixture 는
# "무엇을 재는지 증명되지 않은 검사"다 (K6: 잡히는 증거가 없는 검사는 없는 검사).
d=$(make_fixture '| FR-1 | prd.md | — | | M1 | C01 | 1 | — | 🔵 진행 | — |
| FR-2 | prd.md | — | ✅ | M1 | C01 | 1 | — | ⬜ 대기 | — |')
python3 - "$d/.claude/scripts/check-consistency.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
i = s.index('  # 준비도 — 이 칸은')
j = s.index('\n  case "$state" in\n    *✅*)', i)
open(p, 'w', encoding='utf-8').write(s[:i] + s[j + 1:])
PY
out="$(run "$d")"
case "$out" in
  *"진행 중인데 준비도 점검을 안 돌렸다"*)
    ng "준비도 블록을 들어냈는데도 신호가 났다 — fixture 가 검사기를 실측하지 않는다" ;;
  *) ok "준비도 블록을 들어내면 신호가 사라진다 (fixture 가 진짜로 그 분기를 재고 있다)" ;;
esac

# I 블록도 같은 방식으로 못박는다.
d=$(make_fixture "$I_BASE"); add_registries "$d"
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
python3 - "$d/.claude/scripts/check-consistency.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
i = s.index('# ── I. 문서 등재 대조')
j = s.index('# ── 결과 ──', i)
open(p, 'w', encoding='utf-8').write(s[:i] + s[j:])
PY
out="$(run "$d")"
case "$out" in
  *"사이클 현황 표에 행이 없다"*)
    ng "I 를 들어냈는데도 신호가 났다 — fixture 가 검사기를 실측하지 않는다" ;;
  *) ok "I 를 들어내면 신호가 사라진다 (fixture 가 진짜로 I 를 재고 있다)" ;;
esac

# archive 글롭을 들어내면(닫힌 사이클을 못 보게 되면) 역방향 오탐이 나야 하고,
# 그 오탐을 R12 류 fixture 가 잡아야 한다 — 1회전 K6 이 "이 회귀가 무검출"임을 실측했던 자리다.
d=$(make_fixture "$I_BASE"); add_registries "$d" '| C01 | 첫 | 🔵 |
| C03 | 끝 | ✅ |'
printf '# C01\n' > "$d/docs/plan/cycles/C01-first.md"
printf '# C03\n' > "$d/docs/plan/archive/cycles/C03-done.md"
python3 - "$d/.claude/scripts/check-consistency.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
old = ' "$ROOT"/docs/plan/archive/cycles/*.md'
assert s.count(old) == 1
open(p, 'w', encoding='utf-8').write(s.replace(old, '', 1))
PY
out="$(run "$d")"
case "$out" in
  *"문서가 없다"*) ok "archive 글롭을 들어내면 붉어진다 (역방향 오탐 회귀를 fixture 가 잰다)" ;;
  *) ng "archive 글롭을 들어냈는데도 조용하다 — R12 류 fixture 가 검사기를 실측하지 않는다"
     printf '%s\n' "$out" | sed 's/^/        /' ;;
esac

# J 블록도 같은 방식으로 못박는다 — 들어내면 정상 fixture 의 위반이 조용해져야 한다.
d=$(make_plan "${J_OK/| 파일 모듈 |/| — |}")
python3 - "$d/.claude/scripts/check-consistency.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
i = s.index('# ── J. 계획 깊이')
j = s.index('# 도입 전이면 나머지 검사는', i)
open(p, 'w', encoding='utf-8').write(s[:i] + s[j:])
PY
out="$(run "$d")"
case "$out" in
  *"영향 영역이 비었다"*) ng "J 를 들어냈는데도 신호가 났다 — fixture 가 검사기를 실측하지 않는다" ;;
  *) ok "J 를 들어내면 신호가 사라진다 (fixture 가 진짜로 J 를 재고 있다)" ;;
esac

# 도입 전 조기 종료가 J 의 실패를 삼키지 않는지 — **조기 종료 두 자리 각각에 실제로 뮤테이션을 가한다.**
# 옛 판은 주석만 「finish 를 옛 방식으로 되돌리면」이라 쓰고 **코드는 뮤테이션을 안 가했다**(rc 를 다시 볼 뿐이라
# J1-b 의 중복이었다) — 2회전 별건 #334. 뮤턴트의 rc 를 먼저 단언하는 것이 이 저장소의 규율이다.
mutate_finish() { # $1 fixture경로  $2 그 조기 종료를 특정하는 note 줄
  python3 - "$1/.claude/scripts/check-consistency.sh" "$2" <<'MPY'
import sys
p, marker = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
i = s.index(marker)
j = s.index('  finish "$PRE_TAIL"', i)
assert j - i < 400, "조기 종료가 그 note 바로 뒤에 있어야 한다"
open(p, 'w', encoding='utf-8').write(s[:j] + '  exit 0' + s[j + len('  finish "$PRE_TAIL"'):])
MPY
}

# 조기 종료 ① — 매핑표 파일이 아예 없는 경로
d=$(make_plan "${J_OK/| 파일 모듈 |/| — |}")
mutate_finish "$d" 'docs/spec/source-map.md 가 없다'
out="$(run "$d")"; rc=$?
if [ "$rc" = 0 ]; then ok "조기 종료 ①을 무조건 exit 0 으로 되돌리면 J 실패가 삼켜진다 (J1-b 가 그 회귀를 잰다)"
else ng "조기 종료 ①을 exit 0 으로 되돌렸는데도 rc=$rc — 이 뮤테이션이 아무것도 재지 않는다"
     printf '%s\n' "$out" | sed 's/^/        /'; fi

# 조기 종료 ② — 파일은 있고 행이 없는 경로. `/mdm-plan` 직후의 **실제** 경로다 (#323)
d=$(make_plan "${J_OK/| 파일 모듈 |/| — |}" "$J_TEMPLATE_ROW")
mutate_finish "$d" '요구사항이 없다 (양식만 있음)'
out="$(run "$d")"; rc=$?
if [ "$rc" = 0 ]; then ok "조기 종료 ②를 무조건 exit 0 으로 되돌리면 J 실패가 삼켜진다 (J26-b 가 그 회귀를 잰다)"
else ng "조기 종료 ②를 exit 0 으로 되돌렸는데도 rc=$rc — 이 뮤테이션이 아무것도 재지 않는다"
     printf '%s\n' "$out" | sed 's/^/        /'; fi

echo
if [ "$fail" = 0 ]; then
  echo "정합성 검사 회귀 통과 (H · 준비도 롤업 · I 등재 대조 · J 계획 깊이)"
else
  echo "정합성 검사 회귀 실패"
  exit 1
fi
