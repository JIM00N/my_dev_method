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

# 칸이 **양식 플레이스홀더**인가 — 통째로 <…> 이고 안에 '>' 가 없을 때만 그렇다.
# plan_scan 의 양식 행 판정(앵커 칸)과 **같은 규칙**을 칸 단위로 쓴다. 규칙을 갈라 두면 한쪽만 고쳐진다.
# 이것이 없으면 골격에서 **앵커 칸만 실값으로** 바꾼 계획이 J 를 통째로 빠져나간다 —
# 「채워져 있다 (검사 J)」가 빈 칸 셋만 보던 자리다 (2회전 K1 높음 #342, 반증 확정).
# 골격이 배포하는 `<✅ / —>` 가 `*✅*` 에 매치돼 **가장 엄한 하위 검사를 켜 놓고**,
# 같은 골격의 `<무엇이 시작시키나>` 가 그것을 통과시켰다.
is_ph() {
  case "$1" in
    '<'*'>') case "${1%>}" in *'>'*) return 1 ;; *) return 0 ;; esac ;;
  esac
  return 1
}
# 칸 값을 읽되 **양식 플레이스홀더는 빈 칸으로 본다.**
pcell() {
  local v
  v=$(cell "$1" "$2")
  if is_ph "$v"; then printf ''; else printf '%s' "$v"; fi
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
# 계획이 요구사항에서 멈추면 "어떻게 동작하는가"가 전부 구현 시점으로 미뤄지고,
# 답이 없는 칸은 에이전트가 그 자리에서 지어낸다. 그래서 키트가 만든 계획은
# 기능 → 사양까지 내려가고, 사양마다 영향 영역·선행·먼저를 갖는다.
# 정본: docs/guides/plan.md 「4절 사양 표를 채우는 법」·「정본이 두 벌 되지 않는 이유」.
#
# **출처가 self:plan 인 문서만 본다.** 외부 상류의 스냅샷은 읽기 전용이고 형식이 그쪽 것이라,
# 형식을 강제하면 외부 도구를 쓰는 프로젝트가 첫 검사에서 막힌다 —
# 그쪽은 docs/spec/source-map.md 4절 계약 확인표가 판정으로 다룬다.
#
# **도입(/mdm-adopt) 전에도 돈다.** 계획을 만든 직후가 깊이를 고칠 수 있는 유일한 시점이고,
# 그때는 매핑표가 아직 없어 아래 A~I 는 쉰다.

# 계획 문서를 한 번 훑어 **소제목과 표 데이터 행을 한 스트림**으로 낸다.
# 한 줄 = 여섯 칸(탭 구분): 종류 ⇥ ##절 ⇥ 깊이 ⇥ 제목 ⇥ 머리행 ⇥ 데이터행
#   H … 소제목 (머리행·데이터행은 빈 칸)
#   R … 앵커 열 둘($2·$3)을 **함께** 가진 표의 데이터 행
#
# **앵커 열을 둘 요구한다.** 하나만 보면 계획의 다른 표(낱말 정의·색인)가 걸려 정상 문서가
# 붉어진다 (1회전 K1 #293). 절 번호로 찾지 않는 것은 그대로다 — 골격의 절 번호가 바뀌어도 안 깨지고,
# 앵커 열을 바꾸면 표를 못 찾아 「한 건도 못 찾았다」로 붉어진다 (fail-closed).
#
# **표 안 빈 줄에서 절단하지 않는다** (1회전 K2 치명 #279). 이 저장소는 같은 결함을 이미 두 번
# 확정했다 — table_of(2회전 #269)·reg_table(1회전). 절단이 무음이면 그 아래 행 **전부**가
# 조용히 빠져 「가장 빈 행」이 검사에서 사라진다. table_of 가 빈 줄을 next 로 넘기는 것과 같게 맞춘다.
#
# 걸러내는 것: 코드펜스(``` **와 ~~~ 둘 다** — 1회전 K2 높음 #281) · 4칸 들여쓴 코드블록 ·
# 구분줄 · 양식 행(**앵커 칸**이 통째 <…>). 후행 개행 없는 마지막 줄도 읽는다.
plan_scan() { # $1=파일 $2=앵커 열 A $3=앵커 열 B
  local f="$1" a1="$2" a2="$3" line raw sec="(문서 머리)" lv=0 title="(문서 머리)"
  local hdr="" fence="" cmt="" pre rest h n bare fc ai
  [ -f "$f" ] || return 0
  while IFS= read -r raw || [ -n "$raw" ]; do
    raw="${raw%$'\r'}"                  # CRLF 줄끝 (1회전 K2·K3 독립 #357)
    line="${raw#"${raw%%[![:space:]]*}"}"
    # 코드펜스 — 연 문자와 같은 문자로만 닫힌다
    if [ -n "$fence" ]; then
      case "$line" in
        '```'*) [ "$fence" = 'b' ] && fence="" ;;
        '~~~'*) [ "$fence" = 't' ] && fence="" ;;
      esac
      continue
    fi
    case "$line" in
      '```'*) fence='b'; continue ;;
      '~~~'*) fence='t'; continue ;;
    esac
    # HTML 주석은 **렌더되지 않는다** — 펜스·4칸 코드블록과 같은 부류다 (1회전 K2 높음 #358, 반증 확정).
    # 안 거르면 주석 안 유령 행이 n_spec·close_feat·n_role 을 채워, #320·#327 두 강등이 근거로 삼은
    # 백스톱을 전부 무력화한다. 반대 방향으로는 주석 안 초안 표가 정상 계획을 붉힌다.
    # 한 줄 주석과 줄 중간에서 닫히는 주석도 처리한다 — 닫힌 뒤 남은 글자로 이어서 판정한다.
    while : ; do
      if [ -n "$cmt" ]; then                        # 주석 안에서 줄이 시작한다
        case "$line" in
          *'-->'*) line="${line#*-->}"; cmt="" ;;   # 여기서 닫힌다 — 뒤를 이어서 본다
          *)       line=""; break ;;                # 줄 전체가 주석 안
        esac
      else
        case "$line" in
          *'<!--'*)
            pre="${line%%<!--*}"; rest="${line#*<!--}"
            case "$rest" in
              *'-->'*) line="${pre}${rest#*-->}" ;; # 한 줄에서 열고 닫는다
              *)       line="$pre"; cmt=1 ;;        # 열린 채로 줄이 끝난다
            esac ;;
          *) break ;;
        esac
      fi
    done
    line="${line#"${line%%[![:space:]]*}"}"
    [ -n "$line" ] || continue
    # 앞공백 4칸(또는 탭)부터는 GFM 코드블록이다 — 표·제목은 3칸까지만 렌더된다
    case "$raw" in '    '*|'	'*) continue ;; esac
    case "$line" in
      '#'*)
        h="$line"; n=0
        while [ "${h#\#}" != "$h" ]; do h="${h#\#}"; n=$((n + 1)); done
        # '#' 7개 이상은 GFM 이 제목으로 렌더하지 않는다. '#' 뒤 공백도 요구한다
        if [ "$n" -le 6 ]; then
          case "$h" in
            ' '*|'')
              lv="$n"; title=$(trim "$h"); title="${title//	/ }"
              [ "$n" -le 2 ] && sec="$title"
              hdr=""
              printf 'H\t%s\t%s\t%s\t\t\n' "$sec" "$lv" "$title"
              continue ;;
          esac
        fi
        ;;
    esac
    [ -n "$line" ] || continue          # 표 안 빈 줄은 절단이 아니다 (#279)
    case "$line" in
      '|'*) ;;
      *) hdr=""; continue ;;            # 산문에서 표가 끝난다
    esac
    # escape 파이프는 셀 구분자가 아니다 — 열이 밀리면 빈 칸이 면제되거나 엉뚱한 칸을 읽는다 (#294)
    line="${line//\\|/\&#124;}"
    # 구분줄(|---|:--:|)만 뺀다. '-' 가 없으면 구분줄일 수 없다 —
    # 전부 빈 칸인 행까지 빼면 검사가 잡으려는 「가장 빈 행」이 유일하게 빠져나간다 (#285)
    # 필터를 `data_rows`(`grep -vE '^\|[[:space:]:|-]+$'`)와 **같은 강도**로 맞춘다.
    # 리터럴 `[|: -]` 는 CR·탭을 안 먹어, 구분줄 끝에 **보이지 않는 문자 하나**만 붙으면
    # 구분줄이 데이터 행으로 세어졌다 — 그 행의 칸이 전부 `---` 이라 칸 검사를 다 통과하고
    # `n_spec`·`feat_spec`·`n_role` 백스톱 셋을 동시에 무력화했다 (1회전 K2·K3 독립 #357).
    # `*-*` 가드는 그대로 둔다 — 없으면 전부 빈 칸인 행까지 빠져나간다 (#285).
    # **NBSP(U+00A0)는 여전히 못 먹는다** — `data_rows` 도 같고, 열린 이슈 #272·#264 의 자리다.
    case "$line" in
      *-*) bare="${line//[[:space:]:|-]/}"; [ -n "$bare" ] || continue ;;
    esac
    if [ -z "$hdr" ] || [ -n "$(col_idx "$line" "$a1")" ]; then
      # 머리행 — 앵커 둘을 함께 가져야 이 표를 본다
      if [ -n "$(col_idx "$line" "$a1")" ] && [ -n "$(col_idx "$line" "$a2")" ]; then
        hdr="${line//	/ }"
      else
        [ -z "$hdr" ] && continue
      fi
      continue
    fi
    ai=$(col_idx "$hdr" "$a1")
    fc=$(cell "$line" "$ai")            # 양식 행 판정은 **앵커 칸** 기준이다 (#280)
    case "$fc" in
      '<'*'>') case "${fc%>}" in *'>'*) ;; *) continue ;; esac ;;
    esac
    printf 'R\t%s\t%s\t%s\t%s\t%s\n' "$sec" "$lv" "$title" "$hdr" "$line"
  done < "$f"
}

# 수집 기록에서 self:plan 문서를 고른다.
# **형식 이탈을 조용히 넘기지 않는다** (1회전 K2·K3 높음 #282) — 탭이 공백이 되거나 후행 개행이
# 없으면 J 가 통째로 꺼졌고, 그런데도 「J 만 돌았다」를 출력해 **거짓 통과 주장**이 됐다.
# `|| [ -n "$mline" ]` 가 후행 개행 없는 마지막 줄을 살린다 (plan_scan 과 같은 가드).
TAB=$(printf '\t')
J_TARGETS=""
J_RAN=0
J_PLAN_ROW=0   # docs/upstream/plan.md 가 수집 기록에 **행으로라도** 있는가 (출처는 무엇이든)
if [ -f "$MANIFEST" ]; then
  while IFS= read -r mline || [ -n "$mline" ]; do
    case "$mline" in '#'*|'') continue ;; esac
    # **탭 개수를 센다.** `case ... in *"$TAB"*` 는 「탭 **1개 이상**」이라 4열 가드가 아니었다 —
    # 첫 구분자만 탭이면 jsrc 가 통째로 잘못 잡혀 J 가 조용히 꺼지고 「상류가 외부 도구다」 + rc=0 이
    # 된다 (2회전 K2·K3·K4 3축 독립 #324 — #282 가 닫았다고 한 것의 잔여).
    ntab=0; mrest="$mline"
    while [ "${mrest#*"$TAB"}" != "$mrest" ]; do mrest="${mrest#*"$TAB"}"; ntab=$((ntab + 1)); done
    if [ "$ntab" != 3 ]; then
      bad "docs/upstream/manifest.tsv — 탭 4열이 아닌 줄이 있다 (탭 ${ntab}개 — 4열이면 3개다): '$mline' → 파일<TAB>출처<TAB>수집시각<TAB>sha256 으로 고친다. 형식이 어긋나면 검사 A·J 가 그 줄을 못 보고 조용히 통과한다"
      continue
    fi
    # **`IFS="$TAB" read` 를 쓰지 않는다.** TAB 은 IFS **공백류**라 연속 구분자를 접고 선행 구분자를
    # 버린다 — 그래서 1열·2열이 비면 필드가 밀려 jsrc 가 수집시각이 되고, J 가 조용히 꺼진 채
    # 「상류가 외부 도구다」 + rc=0 이 됐다. #324 가 「닫힘」이라 적은 문구가 글자 그대로 살아 있었다.
    # (1회전 K3 높음 #360, 반증 확정 — bash 3.2·sh·dash·ksh·zsh 전부 동일하게 접힌다)
    # 탭 개수는 위에서 이미 3으로 확인했으므로 `%%`/`#` 로 정확히 넷으로 가른다.
    jf="${mline%%"$TAB"*}";      jrest="${mline#*"$TAB"}"
    jsrc="${jrest%%"$TAB"*}";    jrest="${jrest#*"$TAB"}"
    jat="${jrest%%"$TAB"*}";     jsha="${jrest#*"$TAB"}"
    jf=$(trim "$jf"); jsrc=$(trim "$jsrc"); jat=$(trim "$jat"); jsha=$(trim "$jsha")
    if [ -z "$jf" ] || [ -z "$jsrc" ] || [ -z "$jat" ] || [ -z "$jsha" ]; then
      bad "docs/upstream/manifest.tsv — 네 칸 중 빈 칸이 있다: '$mline' → 파일<TAB>출처<TAB>수집시각<TAB>sha256 을 모두 채운다. 빈 칸을 넘기면 출처를 잘못 읽어 검사 J 가 조용히 꺼진다"
      continue
    fi
    [ "$jf" = "plan.md" ] && J_PLAN_ROW=1
    [ "$jsrc" = "self:plan" ] || continue
    if [ ! -f "$UPSTREAM/$jf" ]; then
      # 검사 A 는 「도입 전」 조기 종료 뒤에 있어 이 창에서는 안 돈다 — J 가 직접 알린다 (#286)
      bad "docs/upstream/$jf — 수집 기록에 있는데 파일이 없다 → /mdm-plan 을 다시 돌리거나 manifest.tsv 의 줄을 지운다"
      continue
    fi
    J_TARGETS="${J_TARGETS}${jf}
"
  done < "$MANIFEST"
fi

# J 가 쉬는 이유를 **아는 만큼만** 말한다. 옛 판은 무조건 「상류가 외부 도구다」라고 했는데,
# 그 말은 수집 기록이 없거나 self:plan 행만 빠졌을 때 **거짓**이다 — 배포본 키트가 정확히 그 상태였다
# (docs/upstream/plan.md 가 물리적으로 있는데 「self:plan 계획 문서도 없다」고 말했다).
# 키트 양식 자신이 *"외부에서 계획을 받아 온 프로젝트라면 이 파일은 지운다 (manifest.tsv 에서도 뺀다)"*
# 라고 그 상태를 금한다. (1회전 K2 높음 #359, 반증 확정 — #282·#286 의 마지막 잔여)
if [ -z "$J_TARGETS" ]; then
  if [ ! -f "$MANIFEST" ] && ls "$UPSTREAM"/*.md >/dev/null 2>&1; then
    # 검사 A 가 같은 것을 보지만 「도입 전」 조기 종료 뒤라 이 창에서는 안 돈다 — J 가 직접 알린다 (#286 과 같은 처방)
    bad "상류 스냅샷은 있는데 수집 기록이 없다: docs/upstream/manifest.tsv — /mdm-plan 또는 /mdm-adopt 로 다시 수집한다. 기록이 없으면 검사 J 가 계획 깊이를 볼 수 없다"
  elif [ -f "$UPSTREAM/plan.md" ] && [ "$J_PLAN_ROW" = 0 ]; then
    caution "docs/upstream/plan.md 가 있는데 수집 기록에 self:plan 으로 기록되지 않았다 — 계획 깊이 검사(J)가 쉰다. /mdm-plan 을 돌려 기록하거나, 상류가 외부 도구라면 그 파일을 지운다 (docs/upstream/plan.md 양식 마지막 줄이 그렇게 지시한다)."
  else
    note "계획 깊이 검사(J)를 건너뛴다 — 출처가 self:plan 인 계획 문서를 수집 기록에서 찾지 못했다 (상류가 외부 도구다)."
  fi
else
  J_RAN=1
  while IFS= read -r jf; do
    [ -n "$jf" ] || continue
    jp="$UPSTREAM/$jf"

    # J-1. 사양 표 — 계층이 끝까지 내려갔고, 행마다 영향 영역·선행·먼저가 채워졌는가
    jscan=$(plan_scan "$jp" "사양" "영향 영역")

    # 어느 '##' 절이 요구사항 절인가 — **절 제목에 「요구사항」이 들어간 절**이다.
    #
    # 옛 판은 「사양 행이 **발견된** 절」로 잡았고, 그것이 순환이었다 (2회전 K2·K1 #320):
    # 사양 표가 아예 없는 절 = 계획이 요구사항에서 멈춘 **바로 그 절** = 전칭 검사가 잡으려는 대상이
    # 구조적으로 사정권 밖이 된다. 요구사항을 두 절로 나누고 둘째가 산문뿐이면 도입 전·후 모두 rc=0 이었다.
    # 절 **번호**는 여전히 못 박지 않는다 — 골격의 번호가 바뀌어도 안 깨진다. 대신 낱말 하나를 요구하고,
    # 그 요구를 docs/guides/plan.md P3 4절이 명시한다 (약속과 장치를 같이 둔다).
    # 대가는 「요구사항」이 든 다른 절 제목(부록·이력)이 계층으로 읽히는 것이라, 가이드가 그것을 금한다.
    n_spec=0; l_hdr=""; ok_cols=0
    js=""; ja=""; jpre=""; jfst=""; jtr=""; jac=""; jrs=""
    cur_req=""; req_feat=0; cur_feat=""; feat_spec=0
    in_req_sec=0; cur_sec=""; sec_req=0; n_req_sec=0
    # 요구사항·기능이 닫힐 때 「아래가 비었나」를 판정한다 — 전칭 주장의 구현이다 (#283).
    # 옛 J 는 파일 전체에 사양 행이 하나만 있어도 통과했는데 DoD 는 「모든 요구사항이 기능으로,
    # 모든 기능이 사양으로」를 (검사 J)로 귀속하고 있었다.
    close_feat() {
      [ -n "$cur_feat" ] || return 0
      [ "$feat_spec" -gt 0 ] || \
        bad "docs/upstream/$jf 「${cur_feat}」 — 이 기능에 사양 표가 없다. 기능에서 멈추면 «어떻게 동작하는가»가 구현 시점으로 미뤄져 그 자리에서 지어내진다 → 사양 표를 만든다 (docs/guides/plan.md P3 4절)"
      cur_feat=""; feat_spec=0
    }
    close_req() {
      [ -n "$cur_req" ] || return 0
      [ "$req_feat" -gt 0 ] || \
        bad "docs/upstream/$jf 「${cur_req}」 — 이 요구사항에 기능(####)이 없다. 요구사항에서 멈춘 것이다 → 요구사항(###) → 기능(####) → 사양(표) 세 층으로 나눈다 (docs/guides/plan.md P3 4절)"
      cur_req=""; req_feat=0
    }
    close_sec() {
      [ "$in_req_sec" = 1 ] || return 0
      [ "$sec_req" -gt 0 ] || \
        bad "docs/upstream/$jf 「${cur_sec}」 — 이 요구사항 절에 요구사항(###)이 없다. 절 제목만 세우고 산문으로 끝난 것이다 → 요구사항(###) → 기능(####) → 사양(표) 세 층으로 나눈다 (docs/guides/plan.md P3 4절)"
      in_req_sec=0; cur_sec=""; sec_req=0
    }

    while IFS="$TAB" read -r jk jsec jlv jtitle jhdr jrow; do
      # 빈 스캔에서 printf 가 내는 **빈 줄 하나**를 사양 행으로 세지 않는다 — 옛 판은 그것이
      # n_spec=1 이 되어 「추출 0 건을 통과로 세지 않는다」가 **정확히 0 건일 때만** 안 떴다 (2회전 K3 #321).
      case "$jk" in H|R) ;; *) continue ;; esac
      if [ "$jk" = H ]; then
        if [ "$jlv" -le 2 ]; then
          close_feat; close_req; close_sec
          case "$jtitle" in
            *요구사항*) in_req_sec=1; cur_sec="$jtitle"; sec_req=0; n_req_sec=$((n_req_sec + 1)) ;;
          esac
        elif [ "$in_req_sec" = 1 ] && [ "$jlv" = 3 ]; then
          close_feat; close_req
          cur_req="$jtitle"; req_feat=0; sec_req=$((sec_req + 1))
        elif [ "$in_req_sec" = 1 ]; then
          close_feat
          cur_feat="$jtitle"; feat_spec=0; req_feat=$((req_feat + 1))
        fi
        continue
      fi

      if [ "$jhdr" != "$l_hdr" ]; then
        l_hdr="$jhdr"; ok_cols=1
        js=$(col_idx "$jhdr" "사양");     ja=$(col_idx "$jhdr" "영향 영역")
        jpre=$(col_idx "$jhdr" "선행");   jfst=$(col_idx "$jhdr" "먼저")
        jtr=$(col_idx "$jhdr" "트리거");  jac=$(col_idx "$jhdr" "동작")
        jrs=$(col_idx "$jhdr" "결과")
        for want in "선행:$jpre" "먼저:$jfst" "트리거:$jtr" "동작:$jac" "결과:$jrs"; do
          if [ -z "${want#*:}" ]; then
            ok_cols=0
            bad "docs/upstream/$jf 「${jtitle}」 — 사양 표에 '${want%%:*}' 열이 없다 → docs/guides/plan.md P3 4절의 열 이름을 그대로 쓴다"
          fi
        done
      fi
      n_spec=$((n_spec + 1)); feat_spec=$((feat_spec + 1))
      if [ -z "$cur_feat" ] && [ "$in_req_sec" = 1 ]; then
        bad "docs/upstream/$jf 「${jtitle}」 — 사양 표가 기능 소제목(####) 아래에 있지 않다. 요구사항 바로 밑에 두면 기능 층이 없는 것이다 → 요구사항(###) → 기능(####) → 사양(표) 세 층으로 나눈다 (docs/guides/plan.md P3 4절)"
        cur_feat="(소제목 없는 표)"
      fi
      [ "$ok_cols" = 1 ] || continue

      sid=$(cell "$jrow" "$js"); [ -n "$sid" ] || sid="(ID 없는 사양 행)"
      case "$(pcell "$jrow" "$ja")" in
        ''|'—'|'-') bad "docs/upstream/$jf $sid — 영향 영역이 비었다. 손댈 모듈·경계를 모르면 무엇을 병렬로 돌릴 수 있는지 계산할 수 없다 → 영역을 적는다 (아무것도 안 건드리는 사양은 없으므로 '—' 는 답이 아니다)" ;;
      esac
      [ -n "$(pcell "$jrow" "$jpre")" ] || \
        bad "docs/upstream/$jf $sid — 선행 칸이 비었다. 선행이 없으면 '—' 라고 적는다 — 빈 칸은 '선행 없음' 과 '아직 안 봤다' 를 구분하지 못한다"
      fst=$(pcell "$jrow" "$jfst")
      [ -n "$fst" ] || \
        bad "docs/upstream/$jf $sid — '먼저' 칸이 비었다. 먼저 만들 묶음이면 ✅, 아니면 '—' → docs/guides/plan.md P3 4절"
      case "$fst" in
        *✅*)
          for want in "트리거:$jtr" "동작:$jac" "결과:$jrs"; do
            case "$(pcell "$jrow" "${want#*:}")" in
              ''|'—'|'-') bad "docs/upstream/$jf $sid — 먼저 만들 묶음인데 '${want%%:*}' 가 비었다. 첫 묶음은 계획 단계에서 동작까지 정한다 (나머지 묶음은 /mdm-ready 가 그때 채운다) → docs/guides/plan.md P3 4절" ;;
            esac
          done ;;
      esac
    done < <(printf '%s\n' "$jscan")
    close_feat; close_req; close_sec
    # 요구사항 절을 하나도 못 찾으면 **조용히 건너뛰지 않는다.** 옛 판은 in_req_sec 이 jlv<=2 H 행
    # 없이는 절대 안 켜져서, setext 제목(===/---)이나 최상위가 ### 인 계획에서 전칭 셋이 통째로
    # 무음이었다 (2회전 K3 #322). 못 찾은 것 자체가 신호다 — fail-closed.
    [ "$n_req_sec" -gt 0 ] || \
      bad "docs/upstream/$jf — 요구사항 절을 찾지 못했다. 검사 J 는 제목에 「요구사항」이 든 '##' 절 안에서 요구사항(###) → 기능(####) → 사양(표) 계층을 센다 → 그 절을 '##' 로 세우고 제목에 「요구사항」을 넣는다 (setext 제목 ===/--- 은 읽지 않는다. docs/guides/plan.md P3 4절)"
    [ "$n_spec" -gt 0 ] || \
      bad "docs/upstream/$jf — 사양 행을 한 건도 찾지 못했다. 계획이 요구사항에서 멈췄거나 사양 표가 양식 그대로다 → 기능(####)과 사양 표를 채운다 (docs/guides/plan.md P3 4절). 추출 0 건을 통과로 세지 않는다"

    # J-2. 권한 표 — 누가 무엇을 할 수 있나는 요구사항 그 자체다 (docs/guides/plan.md P3 2절)
    n_role=0; r_hdr=""; r_ok=0; ri_role=""; ri_deny=""
    while IFS="$TAB" read -r rhdr rrow; do
      if [ "$rhdr" != "$r_hdr" ]; then
        r_hdr="$rhdr"; r_ok=1
        ri_role=$(col_idx "$rhdr" "역할")
        ri_deny=$(col_idx "$rhdr" "거부되면")
        for want in "할 수 있는 것:$(col_idx "$rhdr" "할 수 있는 것")"; do
          if [ -z "${want#*:}" ]; then
            r_ok=0
            bad "docs/upstream/$jf — 권한 표에 '${want%%:*}' 열이 없다 → docs/guides/plan.md P3 2절의 열 이름을 그대로 쓴다"
          fi
        done
      fi
      n_role=$((n_role + 1))
      [ "$r_ok" = 1 ] || continue
      [ -n "$(pcell "$rrow" "$ri_deny")" ] || \
        bad "docs/upstream/$jf 권한 '$(cell "$rrow" "$ri_role")' — '거부되면' 칸이 비었다. 거부 경로가 없는 권한은 화면마다 다르게 구현된다 → 숨김·안내·오류 중 하나를 적거나, 거부가 없으면 '—'"
    done < <(plan_scan "$jp" "역할" "거부되면" | grep "^R$TAB" | cut -f5,6)
    [ "$n_role" -gt 0 ] || \
      bad "docs/upstream/$jf — 역할 × 권한 표를 찾지 못했다. 누가 무엇을 할 수 있나는 요구사항 그 자체이고, 늦게 정하면 화면·데이터를 다시 짜게 된다 → 계획 2절에 표를 만든다. 역할이 없는 프로젝트도 그 사실을 한 줄로 적는다 (docs/guides/plan.md P3 2절)"
  done < <(printf '%s' "$J_TARGETS")
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
