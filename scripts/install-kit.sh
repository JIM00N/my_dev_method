#!/usr/bin/env bash
# dev-kit 설치/업그레이드 스크립트
#
#   설치:      scripts/install-kit.sh <제품 저장소 경로>
#   업그레이드: scripts/install-kit.sh <제품 저장소 경로> --upgrade
#
# 소유권 규칙 (templates/dev-kit/README.md의 표가 정본):
#   - 키트 소유 파일(guides·index·템플릿·.claude)만 교체한다.
#   - 프로젝트 소유 파일(spec 내용·plan·quality 기록·STATUS·ADR)은 절대 덮어쓰지 않는다.
set -uo pipefail

usage() {
  cat <<'USAGE'
사용법: install-kit.sh <제품 저장소 경로> [--upgrade]

  (기본)      처음 적용하는 저장소에 dev-kit을 설치한다.
              CLAUDE.md·docs/가 이미 있으면 중단한다 (--upgrade를 쓰라고 안내).
  --upgrade   이미 키트를 쓰는 저장소에서 키트 소유 파일만 새 판으로 교체한다.
              프로젝트가 채운 spec·plan·quality·status·decisions 내용은 건드리지 않는다.
USAGE
}

die() { echo "오류: $*" >&2; exit 1; }
note() { echo "  $*"; }

SRC="$(cd "$(dirname "$0")/../templates/dev-kit" 2>/dev/null && pwd)" \
  || die "templates/dev-kit 을 찾을 수 없다 (my_dev_method 저장소 안에서 실행해야 한다)"

TARGET=""; MODE="install"
for arg in "$@"; do
  case "$arg" in
    --upgrade) MODE="upgrade" ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; die "알 수 없는 옵션: $arg" ;;
    *) [ -z "$TARGET" ] || die "대상 경로는 하나만 받는다"; TARGET="$arg" ;;
  esac
done
[ -n "$TARGET" ] || { usage; exit 1; }
[ -d "$TARGET" ] || die "대상 디렉터리가 없다: $TARGET (먼저 mkdir + git init)"
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" != "$(cd "$SRC/../.." && pwd)" ] || die "방법론 저장소 자신에는 설치하지 않는다"

KIT_VER=$(sed -n '1s/.*dev-kit v\([0-9.]*\).*/\1/p' "$SRC/CLAUDE.md")
echo "dev-kit v${KIT_VER:-?} → $TARGET (${MODE})"
echo

# ---------- 사전 점검 ----------
if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  note "⚠ 대상이 git 저장소가 아니다. 훅(비밀값·STATUS)은 git 저장소에서만 동작한다 — git init을 먼저 권한다."
else
  if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ]; then
    note "⚠ 대상 작업 트리에 커밋되지 않은 변경이 있다. 설치 후 git diff로 확인할 수 있게 먼저 커밋해 두는 것을 권한다."
  fi
fi
command -v jq >/dev/null 2>&1 || note "⚠ jq가 없다. guard 훅 2개는 jq 없이는 경고만 남기고 통과한다 — brew install jq"
echo

# 파일 하나 복사: 대상이 이미 있고 내용이 다르면 표시
copy_file() { # $1 = kit 기준 상대 경로
  local rel="$1" from="$SRC/$1" to="$TARGET/$1"
  mkdir -p "$(dirname "$to")"
  if [ -e "$to" ] && ! cmp -s "$from" "$to"; then
    cp "$from" "$to"; note "교체: $rel"
  elif [ -e "$to" ]; then
    : # 동일 — 조용히 넘어간다
  else
    cp "$from" "$to"; note "생성: $rel"
  fi
}

# .claude/ 병합: hooks·commands·agents는 파일 단위로 넣고, settings.json은 조심스럽게
merge_claude() {
  local d f rel
  for d in hooks scripts commands agents; do
    for f in "$SRC/.claude/$d"/*; do
      [ -e "$f" ] || continue
      rel=".claude/$d/$(basename "$f")"
      copy_file "$rel"
    done
  done
  chmod 755 "$TARGET"/.claude/hooks/*.sh "$TARGET"/.claude/scripts/*.sh "$TARGET"/.claude/scripts/*.py 2>/dev/null || true
  copy_file ".claude/README.md"
  if [ ! -e "$TARGET/.claude/settings.json" ]; then
    copy_file ".claude/settings.json"
  elif ! cmp -s "$SRC/.claude/settings.json" "$TARGET/.claude/settings.json"; then
    cp "$SRC/.claude/settings.json" "$TARGET/.claude/settings.json.dev-kit"
    note "⚠ .claude/settings.json이 이미 있다 — 덮어쓰지 않았다."
    note "  키트 판을 .claude/settings.json.dev-kit 으로 두었다. hooks 항목을 기존 파일에 손으로 병합한 뒤 지워라."
  fi
}

# 업그레이드에서 교체하는 키트 소유 파일 (README 소유권 표와 일치해야 한다)
KIT_OWNED="
docs/index.md
docs/MOC.md
docs/upstream/index.md
docs/spec/index.md
docs/plan/index.md
docs/plan/archive/index.md
docs/plan/cycles/C00-template.md
docs/plan/stories/ST-000-template.md
docs/quality/index.md
docs/quality/archive/index.md
docs/status/index.md
docs/status/archive/index.md
docs/decisions/index.md
docs/decisions/ADR-000-template.md
AGENTS.md
"

# 이 버전에서 새로 생긴 "프로젝트가 채우는" 양식 — 없을 때만 넣고, 있으면 절대 건드리지 않는다.
# (업그레이드하는 저장소에는 이 파일들이 아예 없기 때문에 필요하다)
KIT_SEED="
docs/spec/source-map.md
docs/upstream/manifest.tsv
docs/upstream/prd.md
docs/upstream/features.md
docs/upstream/userflow.md
docs/upstream/wireframe.md
docs/upstream/plan.md
"

# 생성물은 형상 관리에서 뺀다. 이미 적혀 있으면 건드리지 않는다.
ensure_gitignore() {
  local gi="$TARGET/.gitignore" line
  for line in 'docs/reports/' '.claude/scripts/__pycache__/'; do
    if [ -f "$gi" ] && grep -qxF "$line" "$gi"; then continue; fi
    if [ ! -f "$gi" ]; then
      printf '# dev-kit 생성물 — 정본은 docs/ 의 md 다\n' > "$gi"
    elif ! grep -q 'dev-kit 생성물' "$gi"; then
      printf '\n# dev-kit 생성물 — 정본은 docs/ 의 md 다\n' >> "$gi"
    fi
    printf '%s\n' "$line" >> "$gi"; note "gitignore 추가: $line"
  done
}

copy_if_absent() { # $1 = kit 기준 상대 경로. 이미 있으면 손대지 않는다.
  local rel="$1" to="$TARGET/$1"
  if [ -e "$to" ]; then return 0; fi
  mkdir -p "$(dirname "$to")"
  cp "$SRC/$rel" "$to"; note "생성: $rel (양식 — 이후 프로젝트가 소유한다)"
}

if [ "$MODE" = "install" ]; then
  # ---------- 신규 설치 ----------
  for e in CLAUDE.md docs; do
    [ ! -e "$TARGET/$e" ] || die "$e 가 이미 있다. 키트가 이미 적용된 저장소면 --upgrade를 써라."
  done
  cp "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md";  note "생성: CLAUDE.md"
  cp "$SRC/AGENTS.md" "$TARGET/AGENTS.md";  note "생성: AGENTS.md"
  cp -R "$SRC/docs" "$TARGET/docs";          note "생성: docs/ 전체"
  if [ ! -e "$TARGET/.claude" ]; then
    cp -R "$SRC/.claude" "$TARGET/.claude";  note "생성: .claude/ 전체"
  else
    note "기존 .claude/ 발견 — 통째로 덮지 않고 병합한다:"
    merge_claude
  fi
  chmod 755 "$TARGET"/.claude/hooks/*.sh "$TARGET"/.claude/scripts/*.sh "$TARGET"/.claude/scripts/*.py 2>/dev/null || true
  ensure_gitignore
  cat <<'NEXT'

설치 완료. 이어서 할 일:
  1. CLAUDE.md 상단의 <프로젝트명>, <한 줄 설명> 치환
  2. docs/status/STATUS.md에 시작 시점 기록
  3. (업무 자동화·AX 프로젝트면) docs/guides/addons/business-automation.md 확인 (CLAUDE.md 라우팅 표에 연결돼 있다)
  4. Claude Code에서 /hooks 로 훅 등록 확인
  5. /adopt 를 실행한다 (현재 단계 S0) — 진입점은 하나다.
       저장소 안의 계획 문서를 먼저 찾고, 없으면 밖에 있는지 묻고,
       그래도 없으면 /plan 으로 보내 키트가 직접 만든다.
NEXT
else
  # ---------- 업그레이드 ----------
  [ -e "$TARGET/CLAUDE.md" ] || die "CLAUDE.md가 없다. 키트가 없는 저장소다 — --upgrade 없이 실행해라."
  CUR_VER=$(sed -n '1s/.*dev-kit v\([0-9.]*\).*/\1/p' "$TARGET/CLAUDE.md")
  echo "현재 배포본: v${CUR_VER:-스탬프 없음(0.2.0 이전)} → v${KIT_VER}"
  echo "키트 소유 파일만 교체한다. 프로젝트 소유 파일(spec 내용·plan·quality 기록·STATUS·ADR)은 건드리지 않는다."
  echo
  # guides/ 전체 (하위 addons/ 포함)
  ( cd "$SRC" && find docs/guides -type f -name '*.md' ) | while IFS= read -r rel; do
    copy_file "$rel"
  done
  for rel in $KIT_OWNED; do
    copy_file "$rel"
  done
  for rel in $KIT_SEED; do
    copy_if_absent "$rel"
  done
  merge_claude
  ensure_gitignore
  # CLAUDE.md는 프로젝트명·§6 고유 규칙이 있어 자동 교체하지 않는다
  if ! cmp -s "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md"; then
    cp "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md.dev-kit-new"
    note "⚠ CLAUDE.md는 자동 교체하지 않았다 (프로젝트명·§6 고유 규칙 보존)."
    note "  새 판을 CLAUDE.md.dev-kit-new 로 두었다. diff로 비교해 규칙 부분만 옮기고 지워라."
  fi
  cat <<NEXT

업그레이드 완료 (v${CUR_VER:-?} → v${KIT_VER}). 이어서 할 일:
  1. git diff로 교체된 키트 파일을 확인한다
  2. CLAUDE.md.dev-kit-new 가 있으면 병합 후 삭제 (첫 줄 버전 스탬프를 v${KIT_VER}로)
  3. CHANGELOG의 해당 버전 항목에서 "양식 변경"이 명시된 프로젝트 소유 파일이 있으면 내용을 새 양식으로 옮겨 적는다
  4. docs/status/STATUS.md 최근 결정에 업그레이드 사실 한 줄
NEXT
fi

# settings.json 병합이 안 된 채 끝나면 훅 전부가 죽어 있는데, 커맨드·가이드는 멀쩡히 돌아서
# 문제가 조용하다 — 산문 규칙만 남은 방법론이 된다. 그래서 마지막에 크게 알린다.
# (이번 실행이 만든 것이든 지난 설치가 남긴 것이든, .dev-kit 파일이 남아 있는 한 같은 상태다)
if [ -e "$TARGET/.claude/settings.json.dev-kit" ]; then
  cat <<'WARN'

⚠ 훅이 아직 등록되지 않았다 ─────────────────────────────────────────
  기존 .claude/settings.json 이 있어 키트 판을 덮어쓰지 않았다.
  .claude/settings.json.dev-kit 의 hooks 를 기존 파일에 병합하고 그 파일을 지우기 전까지
  훅 3개(STATUS 갱신 강제 · 의존성 가드 · 비밀값 가드)는 하나도 동작하지 않는다.
  커맨드·가이드는 정상 동작하므로 이 상태는 조용히 지나간다 — 지금 병합해라. 확인: /hooks
WARN
fi
