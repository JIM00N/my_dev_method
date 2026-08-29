#!/usr/bin/env bash
# 문서 정합성 기계 검사 — 사람이 눈으로 대조하지 않게 만드는 장치.
#
# 검사하는 것:
#   A. 상류 스냅샷 무결성   docs/upstream/ 파일이 수집 이후 손으로 고쳐졌는가
#   B. 요구사항 커버리지     준비 미달로 사이클 진입 · 완료인데 테스트 없음 · 검증 조건보다 테스트 적음 · 진행 중인데 사이클 없음
#   C. 재검토 잔존          /mdm-adopt --sync 가 표시한 재검토가 처리되지 않았는가
#   D. 고아 인용            코드·문서가 인용한 ID 가 정본 매핑표에 없는가
#   E. 화면 정합            화면 ID 가 docs/spec/interface.md 에 실제로 있는가
#   F. 참조 깨짐            백틱 `docs/…` 참조가 실재하는가
#   G. 테스트 실재          매핑표 테스트 칸의 이름이 코드에 실제로 있는가
#   H. 마일스톤 배치       모든 요구사항이 마일스톤에 배치됐는가 · 마일스톤 크기 신호 (경고)
#   I. 문서 등재 대조       사이클·ADR 은 문서↔행 양방향 · Story 는 활성 행 유무·잔존 행만 (문서 없는 행은 안 잡는다)
#   J. 계획 깊이            self:plan 계획 문서가 기능·사양까지 내려가고 사양마다 영향 영역·선행·먼저를 갖는가 + 권한 표
#                          (본체는 .claude/scripts/check-plan.py — 마크다운 파싱이라 파이썬이 맡는다. python3 필수)
#
# 정본: docs/spec/source-map.md (요구사항·화면 매핑표)
# 실행: /mdm-plan 끝(도입 전 — J 만) · /mdm-review 1단계 · 사이클 시작 · /mdm-cycle-close · CI
#
# ID 형식을 고정하지 않는다. 상류가 붙인 ID를 그대로 쓰므로(FR-1 · R-AOTSCK · REQ-042 무엇이든),
# 검사기는 매핑표에 실제로 쓰인 값에서 접두사를 유도해 대조한다.
# 열 위치도 고정하지 않는다. 표 머리행의 이름으로 찾으므로 열이 늘어도 깨지지 않는다.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAP="$ROOT/docs/spec/source-map.md"
UPSTREAM="$ROOT/docs/upstream"
MANIFEST="$UPSTREAM/manifest.tsv"

fail=0
warn=0
note() { printf '%s\n' "$*"; }
bad()  { printf '실패  %s\n' "$*"; fail=1; }
caution() { printf '경고  %s\n' "$*"; warn=1; }

# 앞뒤 공백 제거 — 순수 bash. (BSD awk 는 한글 문자열 비교가 어긋나므로 표 처리에 쓰지 않는다)
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else printf 'NOTOOL'; fi
}

# ── 표 읽기 ──────────────────────────────────────────────────────────────
# 절 안의 첫 표를 통째로 뽑는다. 표는 '| ID |' 머리행에서 시작해 비-표 줄에서 끝난다.
# (같은 절 뒤에 오는 '열의 뜻' 설명표는 사이의 산문 줄에서 끊기므로 섞이지 않는다)
# 앞공백 행은 GFM 이 표로 렌더하므로(3칸까지) 읽어야 하고, 표 안 빈 줄은 절단이 아니다 —
# 절단이 무음이면 그 아래 행 전부가 전 검사에서 조용히 빠진다 (2회전 K2 높음 #269, 반증 확정).
# 산문을 만나면 표가 끝난다 — 같은 절 뒤의 「열의 뜻」 설명표와는 그래서 안 섞인다.
table_of() {
  awk -v sec="^## $1\\." '
    { l = $0; sub(/^[ \t]+/, "", l) }
    !inseg { if (l ~ sec) inseg = 1; next }
    l ~ /^## / { exit }
    !intab { if (l ~ /^\|[[:space:]]*ID[[:space:]]*\|/) intab = 1; else next }
    l == "" { next }
    l !~ /^\|/ { exit }
    { print l }
  ' "$MAP"
}
# 구분줄(|---|---|)과 플레이스홀더 양식 행은 뺀다.
# 양식 행의 기준은 **ID 칸(첫 칸)이 통째로 <…>** 인 것 하나다 — 칸 안의 <br> 은 표준 셀 줄바꿈이고
# (1회전 K2 치명 #240), 채워진 행에 남은 <보류> 같은 칸으로 행 전체를 면제하면 빈 칸(—)보다
# placeholder 를 더 관대하게 다루는 역전이 된다 (2회전 K2 높음 #267, 둘 다 반증 확정).
data_rows() { table_of "$1" | tail -n +2 | grep -vE '^\|[[:space:]:|-]+$' | grep -vE '^\|[[:space:]]*<[^|>]*>[[:space:]]*\|'; }
header_of() { table_of "$1" | head -1; }

# 머리행에서 열 이름의 자리 번호(1부터)를 찾는다. 없으면 빈 문자열.
col_idx() {
  local want="$2" i=1 f
  local -a parts
  IFS='|' read -r -a parts <<< "$1"
  for f in "${parts[@]}"; do
    [ "$(trim "$f")" = "$want" ] && { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
}
cell() {
  local idx="$2"
  [ -n "$idx" ] || return 0
  local -a parts
  IFS='|' read -r -a parts <<< "$1"
  trim "${parts[$((idx - 1))]:-}"
}

# 쉼표로 나열된 항목 개수. 빈 칸과 '—' 는 0.
# (bash 3.2 는 set -u 에서 빈 배열 확장이 죽는다 — 빈 입력을 먼저 돌려보내고 확장도 가드한다.
#  가드가 없으면 $() 서브셸만 조용히 죽어 "완료인데 테스트 없음" 검사가 통과해 버린다)
count_items() {
  local n=0 x s
  s=$(trim "$1")
  case "$s" in ''|'—'|'-') printf 0; return ;; esac
  local -a items
  IFS=',' read -r -a items <<< "$s"
  for x in ${items[@]+"${items[@]}"}; do
    case "$(trim "$x")" in ''|'—'|'-') ;; *) n=$((n + 1)) ;; esac
  done
  printf '%s' "$n"
}

REQ_H=""; SCR_H=""
[ -f "$MAP" ] && { REQ_H=$(header_of 2); SCR_H=$(header_of 3); }
req_rows() { data_rows 2; }
scr_rows() { data_rows 3; }

# ── 결과 출력 ────────────────────────────────────────────────────────────
# 끝과 「도입 전」 조기 종료 두 자리에서 같은 형식으로 낸다. 사본을 만들면 한쪽만 고쳐진다.
finish() {
  local tail="${1-}"
  echo
  if [ "$fail" = 0 ] && [ "$warn" = 0 ]; then
    echo "정합성 검사 통과${tail:+ $tail}"
  elif [ "$fail" = 0 ]; then
    echo "정합성 검사 통과 (경고 있음)${tail:+ $tail}"
  else
    echo "정합성 검사 실패 — 위 항목을 해결한다. 검사를 약화시켜 통과시키지 않는다 (절대 규칙 11)."
    echo "유형별 해결 경로: .claude/commands/mdm-review.md 1단계 표. 사용자 판정이 필요하면 STATUS 의 막힌 것에 ⛔ 로 올리고 멈춘다."
    exit 1
  fi
  exit 0
}

# ── J. 계획 깊이 (self:plan 계획 문서) ───────────────────────────────────
# 검사 본체는 **`.claude/scripts/check-plan.py`** 다. 이 자리는 그것을 부르고 결과를 흘려보낸다.
#
# **왜 파이썬으로 옮겼나** — J 의 입력은 사람이 자유롭게 쓰는 마크다운이고, 그 입력 공간은
# 무한 꼬리를 갖는다(CR · 탭 · NBSP · HTML 주석 · 펜스 3종 · escape 파이프 · setext · IFS 접힘).
# 셸로 파싱하던 판에서 같은 결함 계열이 표 리더 다섯 개에서 반복해 확정됐다 —
# table_of(#269) · reg_table · data_rows(#267) · plan_rows(#279) · plan_scan(#357·#358).
# 회전을 더 돌려서 닫히는 종류가 아니라고 판단해 파서를 파이썬으로 옮겼다
# (0.8.0, 사용자 결정 — handoff 0-1절 갈래 A). A~I 는 그대로 셸이다.
#
# **python3 는 필수다 — 없으면 건너뛰지 않고 실패한다.** 조용히 안 도는 검사는 없는 검사다.
# 이 결정으로 python3 가 키트 강제 장치의 **필수 의존**이 됐다 (그전에는 report.py 의 열람용
# 선택 의존이었다). 키트 README 「필요한 것」이 그 사실을 명시한다.
J_RAN=0
J_PLAN_ROW=0
J_PY="$ROOT/.claude/scripts/check-plan.py"
J_STATE=""
if [ ! -f "$J_PY" ]; then
  bad ".claude/scripts/check-plan.py 가 없다 — 계획 깊이 검사(J)를 돌릴 수 없다. 키트를 다시 설치하거나 scripts/install-kit.sh 로 업그레이드한다"
elif ! command -v python3 >/dev/null 2>&1; then
  bad "python3 가 없어 계획 깊이 검사(J)를 돌릴 수 없다 — 키트는 python3 를 요구한다 (README 「필요한 것」). 건너뛰지 않고 실패한다: 조용히 안 도는 검사는 없는 검사다"
else
  J_STATE=$(mktemp 2>/dev/null) || J_STATE=""
  if [ -z "$J_STATE" ]; then
    bad "임시 파일을 만들지 못해 계획 깊이 검사(J)의 상태를 받을 수 없다 (mktemp 실패)"
  else
    trap 'rm -f "$J_STATE"' EXIT
    python3 "$J_PY" --state "$J_STATE"
    J_RC=$?
    case "$J_RC" in
      0) ;;
      1) fail=1 ;;
      2) warn=1 ;;
      *) bad "계획 깊이 검사(J)가 비정상 종료했다 (rc=$J_RC) — .claude/scripts/check-plan.py 를 직접 돌려 원인을 본다" ;;
    esac
    # 상태를 못 읽으면 **모른다고 말하지 않고 실패한다.** J_RAN 을 0 으로 둔 채 넘어가면 꼬리말이
    # 「self:plan 계획 문서도 없다」고 거짓을 말한다 — 옛 판이 정확히 그렇게 틀렸다 (#303·#359).
    # 파일 존재는 따로 안 본다. mktemp 가 이미 만들어 둬서 「없음」은 도달 불가 분기가 되고,
    # 못 잡히는 분기를 남기느니 **열쇠 둘을 실제로 읽었는가** 하나로 판정한다 (빈 파일도 여기서 걸린다).
    J_STATE_OK=0
    while IFS='=' read -r jkey jval; do
      case "$jkey" in
        ran) J_RAN="$jval"; J_STATE_OK=$((J_STATE_OK + 1)) ;;
        plan_row) J_PLAN_ROW="$jval"; J_STATE_OK=$((J_STATE_OK + 1)) ;;
      esac
    done < "$J_STATE"
    [ "$J_STATE_OK" = 2 ] || bad "계획 깊이 검사(J)의 상태 파일이 형식을 벗어났다 (ran·plan_row 둘을 못 읽었다) — .claude/scripts/check-plan.py 를 직접 돌려 원인을 본다"
  fi
fi

# 도입 전이면 나머지 검사는 대조할 것이 없다 — 실패시키지 않되, 상태를 분명히 알린다.
# (검사 J 는 위에서 이미 돌았다. 거기서 실패했으면 finish 가 exit 1 로 내보낸다)
# 꼬리말은 **J 가 실제로 돌았을 때만** J 를 말한다 — 무조건문이면 건너뛴 실행이
# 「J 만 돌았다」고 거짓을 말한다 (1회전 K1·K2 #303).
if [ "$J_RAN" = 1 ]; then PRE_TAIL="(도입 전 — 계획 깊이 검사 J 만 돌았다)"
elif [ -f "$UPSTREAM/plan.md" ] && [ "$J_PLAN_ROW" = 0 ]; then PRE_TAIL="(도입 전 — 대조할 매핑표가 없고, 계획 문서가 self:plan 으로 기록되지 않아 J 가 쉬었다)"
else PRE_TAIL="(도입 전 — 대조할 매핑표가 없고, self:plan 계획 문서도 없다)"; fi
if [ ! -f "$MAP" ]; then
  note "도입 전 — docs/spec/source-map.md 가 없다. /mdm-adopt 를 먼저 실행한다."
  finish "$PRE_TAIL"
fi
if [ -z "$(req_rows)" ] && [ -z "$(scr_rows)" ]; then
  note "도입 전 — docs/spec/source-map.md 에 요구사항이 없다 (양식만 있음). /mdm-adopt 를 먼저 실행한다."
  note "이 상태에서는 어떤 요구사항 근거로 무엇을 만드는지 기계가 대조할 수 없다."
  finish "$PRE_TAIL"
fi

# ── A. 상류 스냅샷 무결성 ────────────────────────────────────────────────
# 상류 산출물의 정본은 상류 쪽이다. 스냅샷을 손으로 고치면 다음 --sync 에서
# 조용히 덮여 사라지므로, 고쳐졌다는 사실 자체를 여기서 잡는다.
if [ -d "$UPSTREAM" ]; then
  if [ ! -f "$MANIFEST" ]; then
    if ls "$UPSTREAM"/*.md >/dev/null 2>&1; then
      bad "상류 스냅샷은 있는데 수집 기록이 없다: docs/upstream/manifest.tsv — /mdm-adopt 로 다시 수집한다"
    fi
  else
    while IFS=$'\t' read -r f _src _at recorded; do
      case "$f" in '#'*|'') continue ;; esac
      target="$UPSTREAM/$f"
      if [ ! -f "$target" ]; then
        bad "수집 기록에 있는 스냅샷이 없다: docs/upstream/$f"
        continue
      fi
      actual=$(sha "$target")
      [ "$actual" = "NOTOOL" ] && { caution "sha256 도구가 없어 스냅샷 무결성 검사를 건너뛴다"; break; }
      if [ "$actual" != "$recorded" ]; then
        bad "스냅샷이 수집 이후 변경됨: docs/upstream/$f — 상류가 정본이다. 손으로 고치지 말고 /mdm-adopt --sync 로 받는다"
      fi
    done < "$MANIFEST"
  fi
fi

# ── B·C. 요구사항 커버리지와 재검토 잔존 ─────────────────────────────────
i_id=$(col_idx "$REQ_H" "ID")
i_ready=$(col_idx "$REQ_H" "준비")
i_cycle=$(col_idx "$REQ_H" "사이클")
i_cond=$(col_idx "$REQ_H" "조건 수")
i_test=$(col_idx "$REQ_H" "테스트")
i_state=$(col_idx "$REQ_H" "상태")
i_recheck=$(col_idx "$REQ_H" "재검토")

for want in ID 사이클 테스트 상태 재검토; do
  case "$want" in
    ID) got=$i_id ;; 사이클) got=$i_cycle ;; 테스트) got=$i_test ;;
    상태) got=$i_state ;; 재검토) got=$i_recheck ;;
  esac
  [ -n "$got" ] || bad "요구사항 매핑표에 '$want' 열이 없다 — docs/spec/source-map.md 2절 머리행을 확인한다"
done
[ -n "$i_cond" ]  || caution "요구사항 매핑표에 '조건 수' 열이 없다 — 검증 조건 대비 테스트 수 검사를 건너뛴다"
[ -n "$i_ready" ] || caution "요구사항 매핑표에 '준비' 열이 없다 — 준비도 검사를 건너뛴다 (/mdm-ready 참조)"

while IFS= read -r row; do
  [ -n "$row" ] || continue
  id=$(cell "$row" "$i_id")
  ready=$(cell "$row" "$i_ready")
  cycle=$(cell "$row" "$i_cycle")
  cond=$(cell "$row" "$i_cond")
  test=$(cell "$row" "$i_test")
  state=$(cell "$row" "$i_state")
  recheck=$(cell "$row" "$i_recheck")

  empty_cycle=0; case "$cycle" in ''|'—'|'-') empty_cycle=1 ;; esac
  n_test=$(count_items "$test")

  # 준비도 — 이 칸은 딸린 Story 슬롯의 롤업이다 (슬롯 자체는 Story 문서가 갖는다).
  # 빈 칸의 정의는 마일스톤 칸과 **같다**: '' 뿐 아니라 '—'·'-' 도 빈 칸이다.
  # 그 둘은 이 표 자신의 「해당 없음」 기호라, 준비 칸만 답으로 받으면 진행 중인 요구사항이 조용히 통과한다.
  # 답이 없는 칸을 남긴 채 구현에 들어가면 에이전트가 그 자리에서 지어낸다.
  if [ -n "$i_ready" ]; then
    case "$state" in
      *🔵*|*🟡*|*✅*)
        case "$ready" in
          ''|'—'|'-') bad "$id — 진행 중인데 준비도 점검을 안 돌렸다 → /mdm-ready 로 딸린 Story 의 슬롯을 판정한다" ;;
          *재판정*) bad "$id — 상류가 바뀌어 준비 판정이 무효가 됐다: $ready → 새 상류 기준으로 /mdm-ready 를 다시 돌린다" ;;
          *❌*) bad "$id — 준비되지 않은 칸이 남아 있다: $ready → 답이 없는 칸은 구현 중에 지어내진다. /mdm-ready 로 채운다" ;;
        esac
        ;;
      *)
        case "$ready" in
          ''|'—'|'-') caution "$id — 준비도 점검 전이다. 사이클에 올리기 전에 /mdm-ready 를 돌린다" ;;
        esac
        ;;
    esac
  fi

  case "$state" in
    *✅*)
      [ "$n_test" = 0 ] && bad "$id — 완료인데 테스트가 없다. 검증 없는 완료는 완료가 아니다 → 테스트를 쓰거나 상태를 되돌린다"
      [ "$empty_cycle" = 1 ] && bad "$id — 완료인데 어느 사이클에서 했는지가 없다 → 매핑표 사이클 칸을 채운다"
      # 검증 조건 수를 아는 경우에만: 조건 하나에 테스트 하나를 요구한다.
      # (테스트가 아예 없는 경우는 바로 위에서 이미 잡았으므로 겹쳐 보고하지 않는다)
      case "$cond" in
        ''|'—'|'-') ;;
        *[!0-9]*) caution "$id — 조건 수 칸이 숫자가 아니다: '$cond' (셀 수 없으면 '—' 로 둔다)" ;;
        *)
          if [ "$n_test" -gt 0 ] && [ "$n_test" -lt "$cond" ]; then
            bad "$id — 검증 조건 $cond 개인데 테스트가 $n_test 개다. 나머지 $((cond - n_test)) 개는 검증되지 않은 채 완료가 된다 → 테스트를 더 쓴다"
          fi
          ;;
      esac
      ;;
    *🔵*|*🟡*)
      [ "$empty_cycle" = 1 ] && bad "$id — 진행 중인데 사이클 인용이 없다 → 매핑표 사이클 칸을 채운다"
      ;;
  esac

  case "$recheck" in
    ''|'—'|'-') ;;
    *) bad "$id — 상류 변경 재검토가 남아 있다: $recheck → /mdm-adopt --sync 7단계로 판정하고 칸을 비운다" ;;
  esac
done < <(req_rows)

# ── D. 고아 인용 ─────────────────────────────────────────────────────────
# 사이클·Story·이슈·코드가 인용한 ID 중 정본 매핑표에 없는 것.
# ID 형식을 고정하지 않으므로, 매핑표에 실제로 쓰인 ID에서 접두사를 유도해 인용 패턴을 만든다.
s_id=$(col_idx "$SCR_H" "ID")
collect_ids() {
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    cell "$row" "$2"; printf '\n'
  done < <($1)
}
known_ids=$( { collect_ids req_rows "$i_id"; collect_ids scr_rows "${s_id:-2}"; } \
             | grep -v '^$' | sort -u )

# 접두사 집합 — 'R-AOTSCK' → 'R', 'FR-12' → 'FR'
prefixes=$(printf '%s\n' "$known_ids" | sed -nE 's/^([A-Za-z]+)-.+$/\1/p' | sort -u)

if [ -z "$prefixes" ]; then
  caution "매핑표의 ID에서 접두사를 뽑지 못해 고아 인용 검사를 건너뛴다 (ID가 '접두사-값' 꼴이 아니다)"
else
  alt=$(printf '%s\n' "$prefixes" | paste -sd'|' -)
  # 앞 글자를 함께 뽑아 ADR-000 같은 다른 ID 체계를 걸러낸다 (\b 는 git grep 의 ERE 에서 안 통한다).
  CITE_RE="[A-Za-z]*($alt)-[A-Za-z0-9]+"
  EXACT_RE="^($alt)-[A-Za-z0-9]+$"
  # 인용을 검사할 곳은 "무엇을 만들고 있는가"를 적는 곳이다: 사이클·Story·이슈·ADR·코드.
  # 빼는 곳과 이유:
  #   docs/upstream           상류 원본. 여기 있는 ID가 정본의 출처지 인용이 아니다
  #   docs/spec/source-map.md 정본 자신
  #   docs/guides · .claude   방법을 설명하는 문서와 도구. 예시 ID가 산문에 들어간다
  #   *template*              양식 파일. 빈칸 표시가 ID 꼴이다
  if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    # --untracked: 아직 커밋하지 않은 작업 중인 파일도 본다 (.gitignore는 존중한다)
    raw=$(git -C "$ROOT" grep --untracked -hoE "$CITE_RE" -- \
            ':!docs/upstream' ':!docs/spec/source-map.md' ':!docs/guides' \
            ':!.claude' ':!*template*' 2>/dev/null)
  else
    raw=$(grep -rhoE "$CITE_RE" "$ROOT/docs" \
            --exclude-dir=upstream --exclude-dir=guides \
            --exclude=source-map.md --exclude='*template*' 2>/dev/null)
  fi
  cited=$(printf '%s\n' "$raw" | grep -E "$EXACT_RE" | sort -u)
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    printf '%s\n' "$known_ids" | grep -qx "$c" || \
      bad "고아 인용: $c — 어딘가가 인용하지만 docs/spec/source-map.md 에 없다 → 오타면 고치고, 새 요구사항이면 /mdm-adopt"
  done < <(printf '%s\n' "$cited")
fi

# ── E. 화면 정합 ─────────────────────────────────────────────────────────
IFACE="$ROOT/docs/spec/interface.md"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  id=$(cell "$row" "${s_id:-2}")
  [ -n "$id" ] || continue
  if [ -f "$IFACE" ]; then
    grep -q "$id" "$IFACE" || \
      bad "$id — 화면 매핑표에 있으나 docs/spec/interface.md 에 없다 → interface.md 에 추가하거나 매핑표에서 뺀다"
  fi
done < <(scr_rows)

# ── F. 참조 깨짐 ─────────────────────────────────────────────────────────
# 백틱 `docs/…` `.claude/…` 참조가 실재하는지. 플레이스홀더는 검사하지 않는다.
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  case "$ref" in *'<'*|*'*'*|*'…'*) continue ;; esac
  [ -e "$ROOT/$ref" ] || bad "깨진 참조: \`$ref\` → 경로를 고치거나 그 파일을 만든다"
done < <(grep -rho --include='*.md' -E '`(docs|\.claude)/[A-Za-z0-9@_<>*./…-]+\.(md|sh|json|tsv)`' \
           "$ROOT/docs" "$ROOT/CLAUDE.md" 2>/dev/null | sed 's/`//g' | sort -u)

# ── G. 테스트 실재 ───────────────────────────────────────────────────────
# B는 테스트 칸의 항목 수만 센다 — 존재하지 않는 이름을 적어도 조건 수 검사까지 통과한다는 뜻이다.
# 그래서 적힌 이름이 코드에 실제로 있는지를 따로 본다. 문서(docs·*.md)와 .claude 는 빼고 찾는다 —
# 사이클·Story 문서가 테스트 이름을 인용하므로, 빼지 않으면 인용이 실재로 오인된다.
G_GIT=0
command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 && G_GIT=1
# 폴백(비-git) 경로는 .gitignore 를 읽을 수 없다. 설치된 의존성·빌드 산출물 안에서 이름이 걸리면
# 없는 테스트가 있는 것으로 통과해 — 검사가 느슨해지는 방향으로 — 속으므로 이름으로 뺀다.
# (git 경로는 --untracked 가 .gitignore 를 존중하므로 이 목록이 필요 없다)
G_SKIP=(--exclude-dir=docs --exclude-dir=.claude --exclude-dir=.git --exclude='*.md'
        --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=dist
        --exclude-dir=build --exclude-dir=target --exclude-dir=.venv)
test_exists() { # $1 = 테스트 이름. 고정 문자열로 찾는다 (이름 형식을 모르므로 정규식을 쓰지 않는다)
  if [ "$G_GIT" = 1 ]; then
    git -C "$ROOT" grep --untracked -qF "$1" -- ':!docs' ':!.claude' ':!*.md' 2>/dev/null
  else
    grep -rqF "${G_SKIP[@]}" "$1" "$ROOT" 2>/dev/null
  fi
}
while IFS= read -r row; do
  [ -n "$row" ] || continue
  id=$(cell "$row" "$i_id")
  tests=$(cell "$row" "$i_test")
  case "$tests" in ''|'—'|'-') continue ;; esac
  IFS=',' read -r -a titems <<< "$tests"
  for t in ${titems[@]+"${titems[@]}"}; do
    t=$(trim "$t")
    case "$t" in ''|'—'|'-') continue ;; esac
    test_exists "$t" || \
      bad "$id — 테스트 '$t' 가 매핑표에는 있는데 코드에는 없다. 이름만 적으면 개수 검사가 속는다 → 그 이름으로 테스트를 쓰거나(RED 먼저), 잘못 적었으면 칸을 고친다"
  done
done < <(req_rows)

# ── H. 마일스톤 배치 ─────────────────────────────────────────────────────
# 마일스톤은 상류가 주지 않는 축이다 — 계획 문서는 "무엇을"의 트리이지 "언제까지"가 아니다.
# /mdm-adopt 7단계가 세우고, 배치가 비면 "언제 만들지 아무도 모르는 요구사항"이 되므로 실패시킨다.
# 크기 신호(사이클 5바퀴 초과 · 요구사항 1개)는 경고다 — 다시 그으라는 신호이지 틀렸다는 판정이 아니다.
# 사이클 수는 매핑표의 사이클 칸에서 센다 (roadmap 을 따로 파싱하지 않는다). 아직 배정 안 된
# 요구사항은 사이클 칸이 비어 있어 낮게 잡히는데, 그건 "아직 계획 안 됨"이므로 맞는 동작이다.
# 정본: docs/plan/index.md 핵심 원칙 5.
i_ms=$(col_idx "$REQ_H" "마일스톤")
if [ -z "$i_ms" ]; then
  caution "요구사항 매핑표에 '마일스톤' 열이 없다 — 마일스톤 배치 검사를 건너뛴다 (docs/spec/source-map.md 2절)"
else
  ms_rows=""    # 요구사항마다 한 줄: 마일스톤
  ms_pairs=""   # 마일스톤|사이클 한 줄씩 (뒤에서 sort -u 로 중복 제거)
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    id=$(cell "$row" "$i_id")
    ms=$(cell "$row" "$i_ms")
    cyc=$(cell "$row" "$i_cycle")
    case "$ms" in
      ''|'—'|'-')
        bad "$id — 마일스톤 배치가 비었다. 언제 만들지 정해지지 않은 요구사항이다 → /mdm-adopt 7단계로 배치한다 (백로그가 아니라 매핑표 '마일스톤' 칸)"
        continue ;;
    esac
    ms_rows="${ms_rows}${ms}
"
    case "$cyc" in
      ''|'—'|'-') ;;
      *)
        IFS=',' read -r -a citems <<< "$cyc"
        for c in ${citems[@]+"${citems[@]}"}; do
          c=$(trim "$c")
          [ -n "$c" ] || continue
          ms_pairs="${ms_pairs}${ms}|${c}
"
        done ;;
    esac
  done < <(req_rows)

  ms_pairs=$(printf '%s' "$ms_pairs" | sort -u)

  # 마일스톤 이름에 공백이 있어도 깨지지 않게 줄 단위로 돈다 ($(...) 워드 스플리팅 금지)
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    nreq=0
    while IFS= read -r l; do
      [ "$l" = "$m" ] && nreq=$((nreq + 1))
    done < <(printf '%s' "$ms_rows")
    ncyc=0
    # ms_pairs 는 $(... | sort -u) 를 거쳐 후행 개행이 없다. '%s' 로 흘리면 마지막 줄이
    # 개행 없이 끝나 read 가 그 줄을 세지 못하고 빠진다 — 검사가 느슨해지는 방향으로 틀린다.
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      [ "${l%%|*}" = "$m" ] && ncyc=$((ncyc + 1))
    done < <(printf '%s\n' "$ms_pairs")

    if [ "$ncyc" -gt 5 ]; then
      caution "$m — 사이클이 ${ncyc}바퀴다. 마일스톤이 너무 크다는 신호 → docs/plan/index.md 핵심 원칙 5로 다시 긋는다"
    fi
    if [ "$nreq" -eq 1 ]; then
      caution "$m — 요구사항이 1개뿐이다. 마일스톤이 사이클의 다른 이름이 됐다는 신호 → 합치거나 다시 긋는다"
    fi
  done < <(printf '%s' "$ms_rows" | sort -u)
fi

# ── I. 문서 등재 대조 ────────────────────────────────────────────────────
# 문서를 만들면 카탈로그에 등재한다 (docs/index.md 파일 목록 원칙). 등재 없는 문서는
# 다음 세션이 존재를 모르고, 문서 없는 행은 카탈로그가 거짓을 말한다 — 양방향을 잡는다.
#   사이클  docs/plan/cycles/ + archive/cycles/  ↔  docs/plan/index.md 「사이클 현황」 표 (행 영구)
#   ADR    docs/decisions/                       ↔  docs/decisions/index.md 「목록」 표 (행 영구)
#   Story  docs/plan/stories/                    ↔  docs/status/STATUS.md 「활성 병렬 작업」 표 (활성 동안만)
# Story 는 문서 없이 행만 있는 것을 잡지 않는다 — 프로파일에 따라 Story 는 문서 없이
# 사이클 문서 안에만 존재하는 것이 정상이라, 잡으면 설계상 오탐이 정상인 검사가 된다.
# 대신 archive 로 닫힌 Story 의 행이 활성 표에 남은 것은 잡는다 (닫힌 행은 지우는 것이 규칙이다).
# 양식 파일(C00·ST-000·ADR-000)은 대상이 아니다.

# 절 제목("## " 뒤 전방 일치) 아래의 표 줄 **전부**를 뽑는다 — 순수 bash.
# (table_of 는 $MAP 전용·'| ID |' 머리행 전제라 다른 파일에는 못 쓴다)
# 첫 비-표 줄에서 끊지 않는다 — 끊으면 빈 줄 뒤에 붙은 행·같은 절의 둘째 표가 안 읽혀,
# 역방향 검사(문서 없는 행)가 조용히 통과한다 (1회전 K2 높음 3건, 반증 확정).
# 코드펜스(```) 안은 절 제목이든 표든 무시한다. 후행 개행 없는 마지막 줄도 읽는다.
reg_table() { # $1=파일 $2=절 제목
  local f="$1" sect="$2" seen=0 fence=0 line
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"   # 앞공백 제거 — GFM 은 3칸까지 표·제목으로 렌더한다 (#268)
    case "$line" in '```'*) if [ "$fence" = 0 ]; then fence=1; else fence=0; fi; continue ;; esac
    [ "$fence" = 1 ] && continue
    if [ "$seen" = 0 ]; then
      case "$line" in "## ${sect}"*) seen=1 ;; esac
      continue
    fi
    case "$line" in "## "*) break ;; "|"*) printf '%s\n' "$line" ;; esac
  done < "$f"
}
# ID 칸의 마크다운 장식을 벗긴다 — **C01**·`C01`·[C01](…) 을 그대로 두면
# 장식된 유령·잔존 행이 판정 필터에서 조용히 면제된다 (1회전 K2 보통).
norm_id() {
  local v; v=$(trim "$1")
  case "$v" in \[*\]*) v="${v#\[}"; v="${v%%\]*}" ;; esac   # [C02](x) 뒤에 텍스트가 붙어도 안쪽만
  v="${v//\*/}"; v="${v//\`/}"
  v=$(trim "$v")
  v="${v%%[[:space:]]*}"                                      # 「C02 (예정)」 → C02 — 뒤 텍스트로 판정을 빠져나가지 않게
  printf '%s' "$v"
}
# 레지스트리 구조 확인 — 파일이 있는데 절의 표나 열이 안 보이면 **실패**시킨다.
# 경고로 두면 열 이름 하나 바꾸는 것으로 검사 I 전체가 exit 0 으로 꺼진다 — CI·게이트는 exit 만 본다.
# 소스맵의 필수 열 부재가 bad 인 것과 같은 강도다 (2회전 K2 보통 #270).
# 반환: 0 정상 · 1 구조 이탈(실패 냄) · 2 파일 없음(도입 전·미설치 — 대조 대상 아님)
reg_check() { # $1=파일 $2=절 제목 $3=열 이름
  local f="$1" rows hdr
  [ -f "$f" ] || return 2
  rows=$(reg_table "$f" "$2")
  if [ -z "$rows" ]; then
    bad "${f#"$ROOT"/} — 「## $2」 절에서 표를 찾지 못했다. 등재 대조(검사 I)가 이 표를 못 본다 → 절 제목·표를 양식대로 되돌린다"
    return 1
  fi
  hdr=$(printf '%s\n' "$rows" | head -1)
  if [ -z "$(col_idx "$hdr" "$3")" ]; then
    bad "${f#"$ROOT"/} — 「## $2」 절의 표에 '$3' 열이 없다. 등재 대조(검사 I)가 이 표를 못 본다 → 열 이름을 양식대로 되돌린다"
    return 1
  fi
}
# 그 표에서 지정한 열의 값들 (한 줄에 하나, 장식 제거). 빈 칸·'—' 는 뺀다.
# 추출 0건은 여기서 실패가 아니다 — 문서 쪽 ID 가 있으면 아래 대조에서 등재 누락으로 잡히고,
# 구조 이탈로 0건이 되는 경우는 reg_check 가 경고를 낸다.
reg_ids() { # $1=파일 $2=절 제목 $3=열 이름
  local rows hdr idx row v
  rows=$(reg_table "$1" "$2")
  [ -n "$rows" ] || return 0
  hdr=$(printf '%s\n' "$rows" | head -1)
  idx=$(col_idx "$hdr" "$3")
  [ -n "$idx" ] || return 0
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    v=$(norm_id "$(cell "$row" "$idx")")
    case "$v" in ''|'—'|'-') continue ;; esac
    printf '%s\n' "$v"
  done < <(printf '%s\n' "$rows" | tail -n +2 | grep -vE '^\|[[:space:]:|-]+$')
}
# 파일명에서 숫자부만 확인해 ID 를 돌려준다. 형식이 다르면 빈 문자열 (대상 아님).
cyc_id_of() { # C01-이름.md → C01
  local b="${1##*/}" id
  id="${b%%-*}"; id="${id%.md}"
  case "${id#C}" in ''|*[!0-9]*) return 0 ;; esac
  [ "$id" = "C00" ] || printf '%s' "$id"
}
pre_id_of() { # $1=파일 $2=접두사. ST-001-이름.md → ST-001
  local b="${1##*/}" pre="$2" num
  case "$b" in "${pre}-"*) ;; *) return 0 ;; esac
  num="${b#*-}"; num="${num%%-*}"; num="${num%.md}"
  case "$num" in ''|*[!0-9]*) return 0 ;; esac
  [ "$num" = "000" ] || printf '%s' "${pre}-${num}"
}

# 사이클 — 양방향. 문서는 활성·archive 어디에 있든 현황 표에 행이 있어야 한다 (행 영구).
reg_check "$ROOT/docs/plan/index.md" "사이클 현황" "#"; cyc_st=$?
cyc_reg=""; [ "$cyc_st" = 0 ] && cyc_reg=$(reg_ids "$ROOT/docs/plan/index.md" "사이클 현황" "#")
cyc_files=""
for f in "$ROOT"/docs/plan/cycles/*.md "$ROOT"/docs/plan/archive/cycles/*.md; do
  [ -e "$f" ] || continue
  id=$(cyc_id_of "$f"); [ -n "$id" ] || continue
  cyc_files="${cyc_files}${id}
"
done
if [ "$cyc_st" != 1 ]; then   # 구조 이탈이면 경고만 — 못 읽는 표를 근거로 판정하지 않는다
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf '%s\n' "$cyc_reg" | grep -qx "$id" || \
      bad "$id — 사이클 문서는 있는데 docs/plan/index.md 사이클 현황 표에 행이 없다. 등재 없는 문서는 다음 세션이 존재를 모른다 → 표에 행을 추가한다 ('#' 칸에 $id)"
  done < <(printf '%s' "$cyc_files" | sort -u)
fi
if [ "$cyc_st" = 0 ]; then
  while IFS= read -r rid; do
    [ -n "$rid" ] || continue
    case "$rid" in C*) ;; *) continue ;; esac        # 'C숫자' 꼴 행만 판정한다 —
    case "${rid#C}" in ''|*[!0-9]*) continue ;; esac  # 접두 확인 없이 숫자만 보면 순번 행(| 3 |)을 오탐한다
    printf '%s' "$cyc_files" | grep -qx "$rid" || \
      bad "$rid — 사이클 현황 표에 행은 있는데 사이클 문서가 없다 (docs/plan/cycles/ · archive/cycles/ 어디에도) → 오타면 행을 고치고, 아니면 문서를 만든다"
  done < <(printf '%s\n' "$cyc_reg")
fi

# ADR — 양방향. ADR 은 archive 로 가지 않는다 (대체·폐기도 행·문서를 남긴다).
reg_check "$ROOT/docs/decisions/index.md" "목록" "#"; adr_st=$?
adr_reg=""; [ "$adr_st" = 0 ] && adr_reg=$(reg_ids "$ROOT/docs/decisions/index.md" "목록" "#")
adr_files=""
for f in "$ROOT"/docs/decisions/ADR-*.md; do
  [ -e "$f" ] || continue
  id=$(pre_id_of "$f" "ADR"); [ -n "$id" ] || continue
  adr_files="${adr_files}${id}
"
done
if [ "$adr_st" != 1 ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf '%s\n' "$adr_reg" | grep -qx "$id" || \
      bad "$id — ADR 문서는 있는데 docs/decisions/index.md 목록 표에 행이 없다. 목록에 없는 ADR 은 다음 세션이 존재를 모른다 → 표에 행을 추가한다 ('#' 칸에 $id)"
  done < <(printf '%s' "$adr_files" | sort -u)
fi
if [ "$adr_st" = 0 ]; then
  while IFS= read -r rid; do
    [ -n "$rid" ] || continue
    case "$rid" in ADR-*) ;; *) continue ;; esac
    case "${rid#ADR-}" in ''|*[!0-9]*) continue ;; esac
    printf '%s' "$adr_files" | grep -qx "$rid" || \
      bad "$rid — ADR 목록 표에 행은 있는데 문서가 없다 (docs/decisions/) → 오타면 행을 고치고, 아니면 문서를 만든다"
  done < <(printf '%s\n' "$adr_reg")
fi

# Story — 활성 문서는 행이 있어야 하고, archive 로 닫힌 문서의 행은 남아 있으면 안 된다.
reg_check "$ROOT/docs/status/STATUS.md" "활성 병렬 작업" "ID"; st_st=$?
st_reg=""; [ "$st_st" = 0 ] && st_reg=$(reg_ids "$ROOT/docs/status/STATUS.md" "활성 병렬 작업" "ID")
if [ "$st_st" != 1 ]; then
  for f in "$ROOT"/docs/plan/stories/ST-*.md; do
    [ -e "$f" ] || continue
    id=$(pre_id_of "$f" "ST"); [ -n "$id" ] || continue
    printf '%s\n' "$st_reg" | grep -qx "$id" || \
      bad "$id — 활성 Story 문서는 있는데 docs/status/STATUS.md 활성 병렬 작업 표에 행이 없다 → 표에 행을 추가한다 ('ID' 칸에 $id)"
  done
fi
if [ "$st_st" = 0 ]; then
  for f in "$ROOT"/docs/plan/archive/stories/ST-*.md; do
    [ -e "$f" ] || continue
    id=$(pre_id_of "$f" "ST"); [ -n "$id" ] || continue
    if printf '%s\n' "$st_reg" | grep -qx "$id"; then
      bad "$id — Story 는 archive 로 닫혔는데 활성 병렬 작업 표에 행이 남아 있다 → 행을 지운다 (닫힌 Story 는 문서만 archive 에 남긴다)"
    fi
  done
fi

# ── 결과 ─────────────────────────────────────────────────────────────────
finish
