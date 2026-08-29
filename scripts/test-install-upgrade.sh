#!/usr/bin/env bash
# install-kit.sh 설치·업그레이드 회귀 검사 — 임시 저장소에 **실제로 돌려서** 본다.
#
# 겨냥하는 것: 0.7.0 개명 이후 설치기가 **옛 이름 파일을 건드리지 않는다**는 것.
#
# 왜 「건드리지 않는다」가 검사 대상인가. 자동 이관을 두 판 만들었고 리뷰가 둘 다 치명으로 잡았다 —
#   1판 `rm -f`: 버전·소유권 확인이 없어 프로젝트 자기 파일을 지웠다.
#   2판 개칭 + 가드 넷: 버전 가드가 `CLAUDE.md` 스탬프에 의존하는데 업그레이드는 그 파일을 갱신하지 않아
#        **실제 경로에서 한 번도 닫히지 않았고**, 그때 fixture 는 손으로 스탬프를 올려
#        **실제 경로가 만들 수 없는 상태**를 재고 있었다.
# 뿌리는 하나다: 설치기는 「이 파일이 키트 것인가」를 알 수 없다. 그 판단이 필요한 일은 사람이 한다
# (2026-08-27 사용자 결정). 그래서 이 fixture 가 재는 것은 **불간섭**이다 — 지우지도, 옮기지도 않는가.
#
# 0.6.0 배포본은 **파일명뿐 아니라 문서 본문의 커맨드 이름까지 되돌려** 합성한다.
# 이름만 되돌린 가짜 0.6.0 은 본문이 이미 새 이름이라 「업그레이드가 키트 문서를 갱신하는가」를
# 구조적으로 못 잰다 (1회전 K4 지적).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/templates/dev-kit"
INSTALL="$ROOT/scripts/install-kit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
ok() { printf '  통과  %s\n' "$*"; }
ng() { printf '  실패  %s\n' "$*"; fail=1; }

OLD_NAMES="
commands/adopt.md
commands/plan.md
commands/ready.md
commands/review.md
commands/stage.md
commands/cycle-close.md
commands/ingest-errors.md
agents/code-review.md
agents/error-learning.md
"

# install-kit.sh 의 RENAMED_0_7_0 **블록만** 뽑는다.
# 파일 전체 grep 이면 다른 목록의 줄에도 걸리고, 한 방향만 보면 그쪽이 **넓어지는** 것을 못 잰다.
renamed_block() { awk '/^RENAMED_0_7_0="$/ { inb=1; next } inb && /^"$/ { exit } inb { print }' "$1"; }

check_list_sync() { # $1 = 설치기 경로
  local a b n
  # 대입이 둘 이상이면 awk 는 첫 블록만 본다 — 그 상태를 통과시키지 않는다 (2회전 K2 지적).
  n=$(grep -c '^RENAMED_0_7_0=' "$1")
  if [ "$n" != 1 ]; then
    ng "install-kit.sh 에 RENAMED_0_7_0 대입이 ${n}개다 — 이 대조는 첫 블록만 본다 (통과로 위장하지 않는다)"
    return
  fi
  a=$(printf '%s\n' $OLD_NAMES | sed '/^$/d' | sort)
  b=$(renamed_block "$1" | sed '/^$/d' | sort)
  if [ -z "$b" ]; then
    ng "RENAMED_0_7_0 블록을 한 줄도 뽑지 못했다 — 추출이 깨졌다 (통과로 위장하지 않는다)"
  elif [ "$a" = "$b" ]; then
    ok "fixture 의 옛 이름 목록이 RENAMED_0_7_0 과 **양방향으로** 일치한다"
  else
    ng "목록이 갈라졌다:
$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | sed 's/^/      /')"
  fi
}

# 0.8.0 신규 파일(검사 J 의 본체)이 그 저장소에 원본과 같게·755 로 도착했는가.
# 이것이 없으면 그 저장소는 검사 J 가 **건너뛰어지지 않고 실패**한다 (fail-closed).
assert_delivers() { # $1 라벨  $2 저장소 경로
  local what="$1" where="$2"
  if [ ! -f "$where/.claude/scripts/check-plan.py" ]; then
    ng "$what — check-plan.py 를 주지 않았다. 그 저장소는 검사 J 가 통째로 실패한다"
    return
  fi
  cmp -s "$KIT/.claude/scripts/check-plan.py" "$where/.claude/scripts/check-plan.py" \
    && ok "$what — check-plan.py 를 원본과 같게 준다 (검사 J 의 본체)" \
    || ng "$what — check-plan.py 를 줬으나 원본과 다르다"
  [ -x "$where/.claude/scripts/check-plan.py" ] \
    && ok "$what — check-plan.py 가 755 로 도착한다" \
    || ng "$what — check-plan.py 가 755 로 도착하지 않았다"
}

# 0.6.0 배포본 합성: 파일명 + **본문의 커맨드·에이전트 이름**까지 옛 것으로 되돌린다.
make_old_install() { # $1 = 이름
  local d="$TMP/$1" rel
  rm -rf "$d"; mkdir -p "$d"
  cp -R "$KIT/.claude" "$d/.claude"
  # 0.8.0 신규 파일은 **실제 0.6.0/0.7.0 배포본에 없다.** `cp -R` 이 내용도 755 도 그대로 옮기므로,
  # 빼지 않으면 업그레이드가 「준다」를 원리적으로 못 잰다 — 설치기가 그 파일을 아예 배달하지 않게
  # 고쳐도 단언이 초록이었다(1회전 K4·K6 2축 독립 #375). 이 파일 머리말이 스스로 경고한 실패형이다.
  rm -f "$d/.claude/scripts/check-plan.py"
  cp -R "$KIT/docs" "$d/docs"
  cp "$KIT/CLAUDE.md" "$d/CLAUDE.md"
  cp "$KIT/AGENTS.md" "$d/AGENTS.md"
  for rel in $OLD_NAMES; do
    mv "$d/.claude/$(dirname "$rel")/mdm-$(basename "$rel")" "$d/.claude/$rel"
  done
  python3 - "$d" <<'PY'
import os, re, sys
root = sys.argv[1]
# lookbehind 에서 `/`·`.` 를 빼면 안 된다 — `/mdm-adopt`(슬래시 커맨드)와
# `commands/mdm-adopt.md`(경로) 가 **가장 흔한 형태**인데 둘 다 앞이 `/` 다.
# 처음 판이 `(?<![\w./-])` 였고 그 탓에 133건이 새 이름 그대로 남아,
# 「업그레이드가 키트 문서를 갈아 준다」 단언이 **공허하게 통과**했다.
rx = re.compile(r'(?<![\w-])mdm-(adopt|plan|ready|review|stage|cycle-close|ingest-errors|'
                r'code-review|error-learning)(?![\w-])')
left = 0
for dp, dns, fns in os.walk(root):
    for fn in fns:
        if not fn.endswith((".md", ".tsv")):
            continue
        p = os.path.join(dp, fn)
        try:
            s = open(p, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        n = rx.sub(lambda m: m.group(1), s)
        if n != s:
            open(p, "w", encoding="utf-8").write(n)
        left += len(re.findall(r'mdm-', n))
# 합성이 실패하면(정규식 드리프트·python 변경) 조용히 통과시키지 않는다.
# 키트 자신의 이름 규칙 설명(`.claude/README.md`)에 남는 `mdm-` 은 정상이라 상한을 둔다.
if left > 12:
    sys.exit("0.6.0 합성이 새 이름을 %d건 남겼다 — 되돌리기가 깨졌다 (합성본이 0.6.0 이 아니다)" % left)
PY
  [ $? = 0 ] || { ng "0.6.0 배포본 합성 실패 — 이 fixture 는 아무것도 재지 못한다"; return 1; }
  sed 's/dev-kit v[0-9.]*/dev-kit v0.6.0/' "$d/CLAUDE.md" > "$d/c.t" && mv "$d/c.t" "$d/CLAUDE.md"
  printf -- '---\ndescription: 이 저장소 자신의 커맨드\n---\n\n본문\n' > "$d/.claude/commands/project-own.md"
  printf -- '---\nname: project-own\n---\n\n본문\n' > "$d/.claude/agents/project-own.md"
  printf '%s' "$d"
}

up() { bash "$INSTALL" "$1" --upgrade > "$TMP/out" 2>&1; UP_RC=$?; }

echo "install-kit.sh — 0.7.0 개명 (설치기는 옛 이름을 건드리지 않는다)"
check_list_sync "$INSTALL"

# ── 1. 0.6.0 → 0.7.0 업그레이드: 불간섭 ──────────────────────────────
d=$(make_old_install fx1)
# **몇 개를 쟀는지 세어 단언한다.** `cksum` 은 없는 파일 하나를 stderr 로 흘리고 나머지를 찍는데
# `$(...)` 가 rc 를 삼킨다 — 그러면 before/after 가 **둘 다 8줄**이 되어 「같다」로 통과하면서
# 실제로는 9개 중 8개만 잰다. 3회전 K3 이 `EXIT=0, all green while measuring only 8 of 9` 로 잡았다.
n_old=$(printf '%s\n' $OLD_NAMES | sed '/^$/d' | grep -c .)
before=$(cd "$d/.claude" && cksum $OLD_NAMES 2>/dev/null | sort)
n_before=$(printf '%s' "$before" | grep -c .)
[ "$n_before" = "$n_old" ] || ng "합성본에 옛 이름이 ${n_before}/${n_old} 개뿐이다 — 이 단언은 부분만 잰다 (통과로 위장하지 않는다)"
up "$d"
[ "$UP_RC" = 0 ] || ng "정상 업그레이드가 rc=$UP_RC 로 끝났다"
after=$(cd "$d/.claude" && cksum $OLD_NAMES 2>/dev/null | sort)
n_after=$(printf '%s' "$after" | grep -c .)
[ "$n_after" = "$n_old" ] || ng "업그레이드 후 옛 이름이 ${n_after}/${n_old} 개다 — 설치기가 파일을 없앴다"
if [ "$before" = "$after" ] && [ "$n_after" = "$n_old" ]; then
  ok "**업그레이드가 옛 이름 9개를 그대로 둔다** — 지우지도, 옮기지도, 고치지도 않는다"
else
  ng "업그레이드가 옛 이름 파일을 건드렸다 (설치기는 키트 것인지 알 수 없다):
$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's/^/      /')"
fi
if ls "$d/.claude/commands" "$d/.claude/agents" | grep -q 'retired\|\.bak\|\.old'; then
  ng "설치기가 옛 이름을 개칭했다 — 불간섭 약속이 깨졌다"
else
  ok "개칭 흔적도 남기지 않는다"
fi

missing=""
for rel in $OLD_NAMES; do
  new=".claude/$(dirname "$rel")/mdm-$(basename "$rel")"
  [ -e "$d/$new" ] || missing="$missing $new"
done
[ -n "$missing" ] && ng "새 이름이 들어오지 않았다 —$missing" || ok "새 이름 9개가 들어온다"

if grep -q '0.7.0 에서 개명된 것과 같은 이름의 파일이 있다' "$TMP/out" \
   && grep -q '앞으로도 건드리지 않는다' "$TMP/out"; then
  ok "**건드리지 않는 대신 알린다** — 무엇이 남았는지와 앞으로도 안 건드린다는 것까지"
else
  ng "옛 이름이 9개 남았는데 알리지 않거나, 앞으로의 약속을 말하지 않았다"
fi
grep -q '4-1' "$TMP/out" && ok "손 절차(키트 README 4-1)로 안내한다" \
  || ng "알리기만 하고 어디를 보라는 말이 없다 — 사용자의 다음 행동이 결정되지 않는다"

if [ -e "$d/.claude/commands/project-own.md" ] && [ -e "$d/.claude/agents/project-own.md" ]; then
  ok "목록에 없는 그 저장소 자신의 커맨드·에이전트도 그대로다"
else
  ng "키트가 만들지 않은 파일을 건드렸다"
fi

# ── 2. 키트 소유 문서는 새 이름으로 갱신된다 ─────────────────────────
# 0.6.0 합성이 **본문까지** 되돌렸으므로 이 단언이 실질을 잰다.
stale=$(grep -rlE '(^|[^A-Za-z0-9_./-])/(adopt|plan|ready|review|stage|cycle-close|ingest-errors)([^A-Za-z0-9_-]|$)' \
          "$d/docs/guides" "$d/docs/index.md" "$d/docs/MOC.md" 2>/dev/null | sed "s|$d/||" | tr '\n' ' ')
if [ -n "$stale" ]; then
  ng "업그레이드가 교체하는 **키트 소유 문서**에 옛 이름이 남았다 — $stale"
else
  ok "업그레이드가 키트 소유 문서(guides·index·MOC)를 새 이름으로 갈아 준다"
fi

# ── 3. 프로젝트 데이터가 실리는 카탈로그 표는 보존된다 (KIT_OWNED → KIT_SEED) ──
d2=$(make_old_install fx2)
printf '\n| C01 | 첫 사이클 | 진행 |\n' >> "$d2/docs/plan/index.md"
printf '\n| ADR-001 | 스택 결정 | 채택 |\n' >> "$d2/docs/decisions/index.md"
up "$d2"
if grep -q 'C01' "$d2/docs/plan/index.md" && grep -q 'ADR-001' "$d2/docs/decisions/index.md"; then
  ok "업그레이드가 카탈로그 행(사이클 현황·ADR 목록)을 보존한다"
else
  ng "업그레이드가 카탈로그 행을 지웠다 — 검사 I 가 그것을 사용자 과실로 보고하게 된다"
fi

# ── 4. 신규 설치도 같은 이름의 남의 파일을 건드리지 않는다 ───────────
d3="$TMP/fx3"; rm -rf "$d3"; mkdir -p "$d3/.claude/commands"
printf -- '---\ndescription: 이 저장소 자신의 review\n---\n\nOWN\n' > "$d3/.claude/commands/review.md"
bash "$INSTALL" "$d3" > "$TMP/out3" 2>&1
if grep -q OWN "$d3/.claude/commands/review.md" 2>/dev/null; then
  ok "신규 설치가 같은 이름의 남의 파일을 건드리지 않는다"
else
  ng "신규 설치가 대상 저장소 자신의 .claude/commands/review.md 를 건드렸다"
fi
grep -q '앞으로도 건드리지 않는다' "$TMP/out3" \
  && ok "신규 설치도 같은 약속을 인쇄한다 (다음 업그레이드가 그 말을 지킨다)" \
  || ng "신규 설치 안내가 지키지 못할 약속을 하거나 아무 말도 하지 않았다"

# **업그레이드 전에** 신규 설치의 배달을 잰다 — 뒤로 미루면 업그레이드가 결손을 메꾼다 (#375).
assert_delivers "신규 설치" "$d3"

# 그 상태에서 이어서 업그레이드해도 그대로여야 한다 — 두 경로가 같은 약속을 지키는지.
up "$d3"
grep -q OWN "$d3/.claude/commands/review.md" 2>/dev/null \
  && ok "**설치가 남긴 남의 파일이 다음 업그레이드에서도 그대로다**" \
  || ng "설치가 「앞으로도 안 건드린다」고 한 파일을 다음 업그레이드가 건드렸다"

# ── 5. 0.8.0 신규 파일 전달 — **업그레이드 경로** ─────────────────────
# 신규 설치 경로는 4절에서 **업그레이드 전에** 이미 쟀다 (여기서 재면 업그레이드가 결손을 메꿔
# 라벨과 실제로 측정되는 것이 어긋난다 — 1회전 K6 #375).
assert_delivers "업그레이드" "$d"

# ── 뮤테이션 자기검증 ────────────────────────────────────────────────
# 파괴적 이관을 되살리면 불간섭 케이스가 **반드시** 붉어져야 한다.
# 뮤턴트가 돌지 않으면 「안 건드렸다」가 저절로 참이 되므로, 먼저 뮤턴트의 rc·출력을 단언한다.
echo "뮤테이션 자기검증"
mkdir -p "$TMP/fake/scripts" "$TMP/fake/templates"
ln -s "$KIT" "$TMP/fake/templates/dev-kit"
mut="$TMP/fake/scripts/install-kit.sh"
sed 's|^  warn_renamed$|  for _r in $RENAMED_0_7_0; do rm -f "$TARGET/.claude/$_r"; done|' "$INSTALL" > "$mut"
if ! grep -q 'rm -f "\$TARGET/.claude/\$_r"' "$mut"; then
  ng '뮤테이션 지점(들여쓴 warn_renamed 호출 줄)을 찾지 못했다 — 이 fixture 를 갱신한다'
else
  d4=$(make_old_install fx4)
  bash "$mut" "$d4" --upgrade > "$TMP/out4" 2>&1; mrc=$?
  if [ "$mrc" != 0 ] || ! grep -q '업그레이드 완료' "$TMP/out4"; then
    ng "뮤턴트가 정상 종료하지 않았다 (rc=$mrc) — 이 자기검증은 아무것도 재지 못한다:
$(tail -2 "$TMP/out4" | sed 's/^/      /')"
  elif [ -e "$d4/.claude/commands/adopt.md" ]; then
    ng "파괴적 이관을 되살렸는데 옛 이름이 남았다 — 이 fixture 는 불간섭을 재고 있지 않다"
  else
    ok "파괴적 이관을 되살리면 옛 이름이 사라진다 (fixture 가 진짜로 불간섭을 재고 있다)"
  fi
fi

echo
if [ "$fail" = 0 ]; then
  echo "install-kit.sh 설치·업그레이드 회귀 통과"
else
  echo "install-kit.sh 설치·업그레이드 회귀 실패"
  exit 1
fi
