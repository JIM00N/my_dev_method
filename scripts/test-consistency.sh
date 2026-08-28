#!/usr/bin/env bash
# 정합성 검사 회귀 검사 — 임시 fixture 저장소에서 실측한다.
#   H. 마일스톤 배치
#   B·C 안의 **준비도 롤업 4분기**(실패 3 · 경고 1)와 열 부재 (이슈 #091)
#   I. 문서 등재 대조 — 미등재 문서 3유형 · 문서 없는 행 2유형 · 닫힌 Story 행 잔존 · 오탐 경계 2종
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

echo
if [ "$fail" = 0 ]; then
  echo "정합성 검사 회귀 통과 (H · 준비도 롤업 · I 등재 대조)"
else
  echo "정합성 검사 회귀 실패"
  exit 1
fi
