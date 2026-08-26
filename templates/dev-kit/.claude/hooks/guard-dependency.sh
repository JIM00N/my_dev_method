#!/usr/bin/env bash
# PreToolUse(Bash · Write|Edit) 훅 — docs/spec/stack.md에 없는 패키지 도입을 막는다.
# CLAUDE.md 절대 규칙 4의 기계적 강제판.
# 판단이 불확실하면 통과시킨다. 오탐으로 작업을 막는 것보다 낫다.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STACK="$ROOT/docs/spec/stack.md"
input=$(cat 2>/dev/null || true)

if ! command -v jq >/dev/null 2>&1; then
  echo "guard-dependency: jq가 없어 의존성 검사를 건너뛴다. 강제를 원하면 jq를 설치하라." >&2
  exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)

# 이름에서 버전 지정을 떼어낸다: pkg@1.2 / pkg==1.2 / pkg>=1 / @scope/pkg@1
strip_version() {
  local t="$1"
  case "$t" in
    @*) printf '%s' "$(printf '%s' "$t" | sed -E 's#^(@[^/]+/[^@]+).*$#\1#')" ;;
    *)  printf '%s' "$(printf '%s' "$t" | sed -E 's/[@=<>!~[].*$//')" ;;
  esac
}

# stack.md 표의 "선택" 열(3번째 칸)만 근거로 쓴다. 영역 이름(2번째 칸)이나 탈락 대체제(4번째 칸),
# 파일 전체 부분 문자열 검색은 오탐·미탐을 동시에 낸다.
stack_tokens() {
  awk -F'|' '/^[[:space:]]*\|/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
    if ($3 != "" && $3 !~ /^[-: ]+$/) print $3
  }' "$STACK" 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' ,()·/' '\n\n\n\n\n\n' \
  | grep -Ev '^$|^[0-9.]+$' | sort -u
}

# pkg가 선택 목록에 있는가 — 정확 일치 또는 "토큰-부속" 형태(react → react-dom, @types/react)
in_stack() {
  local pkg tok base
  pkg=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  base="${pkg#@types/}"; base="${base##*/}"    # @scope/name → name 도 함께 본다
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    [ "$pkg" = "$tok" ] && return 0
    [ "$base" = "$tok" ] && return 0
    case "$pkg" in "$tok"[-_./]*) return 0 ;; esac
    case "$base" in "$tok"[-_./]*) return 0 ;; esac
  done <<< "$TOKENS"
  return 1
}

check_missing() {   # $1: 개행 구분 패키지 목록 → 전역 missing 세팅
  missing=""
  if [ ! -f "$STACK" ]; then
    cat >&2 <<MSG
docs/spec/stack.md가 없다. 기술 스택을 확정하기 전에 패키지를 도입하지 않는다.
docs/guides/S4-architecture.md 2부를 먼저 수행하라.
도입하려던 것: $(printf '%s' "$1" | tr '\n' ' ')
MSG
    exit 2
  fi
  TOKENS=$(stack_tokens)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    in_stack "$p" || missing="$missing $p"
  done <<< "$1"
}

report_block() {
  cat >&2 <<MSG
stack.md에 없는 기술 도입 시도 — 차단 (CLAUDE.md 절대 규칙 4).

docs/spec/stack.md 결정 표의 "선택" 열에서 찾을 수 없는 항목:$missing

임의로 고르지 않는다. 먼저 사용자에게
  ① 어떤 기술 영역인가 ② 장점 ③ 단점·종속성 ④ 검토한 대체제와 추천 이유
를 제시하고 승인을 받은 뒤, docs/spec/stack.md의 결정 표
[영역 | 선택 | 탈락 대체제 | 선택 이유 | 결정일]에 추가하라.
되돌리기 어려운 선택이면 docs/decisions/에 ADR도 남긴다.
MSG
  exit 2
}

# ---------- Write / Edit 경로: 의존성 매니페스트 직접 편집 ----------
if [ "$tool" != "Bash" ] && [ -n "$tool" ]; then
  fpath=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
  # MultiEdit는 edits[] 배열로 온다 — 새 문자열을 전부 합쳐서 본다
  content=$(printf '%s' "$input" \
    | jq -r '.tool_input.content // .tool_input.new_string // ([.tool_input.edits[]?.new_string // ""] | join("\n"))' 2>/dev/null || true)
  [ -n "$fpath" ] && [ -n "$content" ] || exit 0
  fname=$(basename "$fpath")
  pkgs=""
  case "$fname" in
    package.json|composer.json)
      # 값이 버전 범위 형태인 "이름": "^1.2.3" 행만 의존성으로 본다
      pkgs=$(printf '%s\n' "$content" \
        | grep -Eo '"[@A-Za-z0-9][A-Za-z0-9@/_.-]*"[[:space:]]*:[[:space:]]*"(workspace:|npm:|file:|link:|git\+|[\^~><=]|[0-9])' \
        | sed -E 's/^"([^"]+)".*/\1/' \
        | grep -Ev '^(version|name|type|main|module|types|node|npm|pnpm|yarn|packageManager|engines)$' || true) ;;
    requirements*.txt)
      pkgs=$(printf '%s\n' "$content" | grep -Eo '^[A-Za-z0-9][A-Za-z0-9._-]*[[:space:]]*([=<>~!]=|>|<|\[|$)' \
        | sed -E 's/[[:space:]]*([=<>~!<>[].*)?$//' || true) ;;
    pyproject.toml)
      pkgs=$(printf '%s\n' "$content" \
        | grep -Eo '"[A-Za-z0-9][A-Za-z0-9._-]*[[:space:]]*[=<>~!][^"]*"|^[A-Za-z0-9][A-Za-z0-9._-]*[[:space:]]*=[[:space:]]*["{^]' \
        | sed -E 's/^"//; s/[[:space:]]*[=<>~!{^"].*$//' \
        | grep -Ev '^(python|version|name)$' || true) ;;
    Cargo.toml)
      pkgs=$(printf '%s\n' "$content" | grep -Eo '^[A-Za-z0-9][A-Za-z0-9_-]*[[:space:]]*=[[:space:]]*["{]' \
        | sed -E 's/[[:space:]]*=.*$//' \
        | grep -Ev '^(name|version|edition|authors|description|license)$' || true) ;;
    go.mod)
      pkgs=$(printf '%s\n' "$content" | grep -Eo '^[[:space:]]*(require[[:space:]]+)?[a-z0-9.-]+\.[a-z]{2,}/[^[:space:]]+[[:space:]]+v[0-9]' \
        | sed -E 's/^[[:space:]]*(require[[:space:]]+)?//; s/[[:space:]]+v[0-9]$//' || true) ;;
    Gemfile)
      pkgs=$(printf '%s\n' "$content" | grep -Eo "^[[:space:]]*gem[[:space:]]+['\"][A-Za-z0-9_-]+" \
        | sed -E "s/^[[:space:]]*gem[[:space:]]+['\"]//" || true) ;;
    *) exit 0 ;;
  esac
  pkgs=$(printf '%s\n' "$pkgs" | grep -v '^$' | sort -u || true)
  [ -n "$pkgs" ] || exit 0
  check_missing "$pkgs"
  [ -n "$(printf '%s' "$missing" | tr -d ' ')" ] || exit 0
  report_block
fi

# ---------- Bash(설치 명령) 경로 ----------
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -n "$cmd" ] || exit 0

pkgs=""
while IFS= read -r seg || [ -n "$seg" ]; do
  [ -n "$seg" ] || continue
  set -f                      # 글롭 확장 금지 — npm install * 같은 입력 보호
  # shellcheck disable=SC2086
  set -- $seg
  set +f
  # 환경 변수 대입·래퍼 명령을 벗긴다 (sudo npm install … 등)
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*|sudo|env|command|nohup|nice|time) shift ;;
      *) break ;;
    esac
  done
  [ $# -ge 2 ] || continue
  mgr="$(basename "$1")"; sub="$2"; take=0; skip=2
  case "$mgr:$sub" in
    npm:install|npm:i|npm:add|pnpm:install|pnpm:i|pnpm:add|yarn:add|bun:add|bun:install) take=1 ;;
    pip:install|pip3:install|pipx:install|uv:add|poetry:add) take=1 ;;
    cargo:add|cargo:install|gem:install|composer:require|go:get|go:install|brew:install) take=1 ;;
    uv:pip)      [ "${3:-}" = "install" ] && { take=1; skip=3; } ;;
    python:-m|python3:-m) case "${3:-}:${4:-}" in pip:install|pip3:install) take=1; skip=4 ;; esac ;;
  esac
  [ "$take" = 1 ] || continue
  shift "$skip"
  skip_next=0
  for tok in "$@"; do
    [ "$skip_next" = 1 ] && { skip_next=0; continue; }
    case "$tok" in
      # 값을 갖는 플래그 — 다음 토큰은 패키지가 아니다 (pip install -r requirements.txt 등)
      -r|--requirement|-c|--constraint|-e|--editable|-t|--target|-i|--index-url|--extra-index-url|-f|--find-links|-w|--workspace|--prefix|--registry|-P|--python) skip_next=1; continue ;;
      -*|.|./*|/*|../*|'$'*|'`'*|'*'|'?') continue ;;   # 플래그·로컬 경로·치환·글롭은 대상 아님
    esac
    name="$(strip_version "$tok")"
    [ -n "$name" ] && pkgs="$pkgs $name"
  done
done < <(printf '%s\n' "$cmd" | tr ';|&\n' '\n\n\n\n')

# 인자 없는 npm install / pnpm i 등은 lockfile 복원이므로 통과
pkgs="$(printf '%s' "$pkgs" | tr ' ' '\n' | grep -v '^$' | sort -u || true)"
[ -n "$pkgs" ] || exit 0

check_missing "$pkgs"
[ -n "$(printf '%s' "$missing" | tr -d ' ')" ] || exit 0
report_block
