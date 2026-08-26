#!/usr/bin/env bash
# PreToolUse(Bash · Write|Edit) 훅 — 비밀값이 저장소에 들어가는 것을 막는다.
# CLAUDE.md 절대 규칙 12(비밀값)·S4 4부의 기계적 강제판.
# 발견한 값 자체는 출력하지 않는다. 파일·건수만 알린다.
# 판단이 불확실하면 통과시킨다 (fail-open). 단, 통과 사유는 침묵하지 않는다.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
input=$(cat 2>/dev/null || true)

if ! command -v jq >/dev/null 2>&1; then
  echo "guard-secrets: jq가 없어 비밀값 검사를 건너뛴다. 강제를 원하면 jq를 설치하라." >&2
  exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)

# 비밀값 형태 문자열 (내용 검사용)
SECRET_RE='AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{10,}|rk_live_[A-Za-z0-9]{10,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{15,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|[a-z][a-z0-9+]{1,20}://[^:@/[:space:]]+:[^@[:space:]]{6,}@|(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)[[:space:]]*[:=][[:space:]]*.[A-Za-z0-9/+_-]{12,}'
# 오탐 제외 (참조·플레이스홀더·테스트 값·무결성 해시)
ALLOW_RE='process\.env|os\.environ|getenv|ENV\[|<[A-Za-z_]+>|xxx|dummy|example|placeholder|your-|changeme|test[_-]?(key|token|secret|password)|sha256-|sha512-|integrity'
# 이름만으로 차단하는 비밀 파일 (예제 파일 제외)
SECRET_FILE_RE='(^|/)\.env($|\.)|(^|/)id_(rsa|dsa|ecdsa|ed25519)($|\.)|\.p12$|\.pfx$|(^|/)credentials\.json$|serviceAccount[^/]*\.json$'
EXAMPLE_FILE_RE='\.env\.(example|sample|template)$'
# 내용에 PRIVATE KEY가 있을 때만 차단하는 파일 (공개 인증서 .pem, Keynote .key 오탐 방지)
MAYBE_KEY_FILE_RE='\.pem$|\.key$'

block() {
  {
    echo "$1 — 차단 (CLAUDE.md 절대 규칙 12 · S4 안정성)."
    echo
    [ -n "${2:-}" ] && { printf '%s\n' "$2"; echo; }
    cat <<'MSG'
할 것:
  1. 비밀값을 코드·커밋에서 제거한다 (git restore --staged <파일> / 파일 수정 취소)
  2. .gitignore에 해당 경로를 추가한다 (.env.example 류만 저장소에 남긴다)
  3. 값은 환경 변수·비밀값 관리 도구로 옮기고 코드에서는 참조만 한다
  4. 이미 커밋·푸시된 적이 있으면 그 키를 폐기하고 재발급한다

오탐이면 docs/spec/code-conventions.md 5-1의 예외 표에 그 한 건을 기록한 뒤 진행하라.
MSG
  } >&2
  exit 2
}

# ---------- Write / Edit 경로 ----------
if [ "$tool" != "Bash" ] && [ -n "$tool" ]; then
  fpath=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
  content=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null || true)
  [ -n "$fpath" ] || exit 0
  rel="${fpath#"$ROOT"/}"

  # 형상 관리에서 이미 제외된 파일이면 비밀값이 있어도 커밋되지 않는다 — 통과
  if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$ROOT" check-ignore -q -- "$rel" 2>/dev/null && exit 0
  fi

  if printf '%s' "$rel" | grep -Eq "$SECRET_FILE_RE" && ! printf '%s' "$rel" | grep -Eq "$EXAMPLE_FILE_RE"; then
    block "비밀 파일을 형상 관리 대상 경로에 쓰려 한다" "대상: $rel (먼저 .gitignore에 추가하라)"
  fi
  if [ -n "$content" ]; then
    hits=$(printf '%s\n' "$content" | grep -Ev "$ALLOW_RE" | grep -Eic "$SECRET_RE" || true)
    [ "${hits:-0}" -gt 0 ] && block "비밀값 형태의 문자열을 형상 관리 대상 파일에 쓰려 한다" "대상: $rel · ${hits}건"
  fi
  exit 0
fi

# ---------- Bash(git commit) 경로 ----------
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -n "$cmd" ] || exit 0

# 세그먼트 단위로 git … commit 호출을 찾는다 (경로 호출·git -C·env 접두어 포함)
is_commit=0; all_flag=0
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  set -f
  # shellcheck disable=SC2086
  set -- $seg
  set +f
  # 환경 변수 대입·래퍼 명령을 벗긴다
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*|sudo|env|command|nohup|nice|time) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || continue
  [ "$(basename "$1")" = "git" ] || continue
  shift
  seen_commit=0
  for tok in "$@"; do
    case "$tok" in
      commit) seen_commit=1 ;;
      -a|--all) [ "$seen_commit" = 1 ] && all_flag=1 ;;
      --*) : ;;
      -*a*) [ "$seen_commit" = 1 ] && all_flag=1 ;;   # -am, -qam 등 결합 플래그 (--* 는 위에서 걸러짐)
    esac
  done
  [ "$seen_commit" = 1 ] && is_commit=1
done < <(printf '%s\n' "$cmd" | tr ';|&\n' '\n\n\n\n')

[ "$is_commit" = 1 ] || exit 0
command -v git >/dev/null 2>&1 || exit 0
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# -a/--all 커밋은 실행 시점에 추적 파일 전체를 스테이징하므로 git diff HEAD 를 본다
if [ "$all_flag" = 1 ]; then
  files=$(git -C "$ROOT" diff HEAD --name-only 2>/dev/null || true)
  diff_cmd=(git -C "$ROOT" diff HEAD -U0)
else
  files=$(git -C "$ROOT" diff --cached --name-only 2>/dev/null || true)
  diff_cmd=(git -C "$ROOT" diff --cached -U0)
fi
[ -n "$files" ] || exit 0

bad_files=$(printf '%s\n' "$files" | grep -Ei "$SECRET_FILE_RE" | grep -Evi "$EXAMPLE_FILE_RE" || true)

# .pem/.key 는 내용에 PRIVATE KEY 가 있을 때만 비밀 파일로 본다
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if printf '%s' "$f" | grep -Eqi "$MAYBE_KEY_FILE_RE"; then
    if git -C "$ROOT" show ":$f" 2>/dev/null | grep -q 'PRIVATE KEY' \
       || grep -q 'PRIVATE KEY' "$ROOT/$f" 2>/dev/null; then
      bad_files=$(printf '%s\n%s' "$bad_files" "$f")
    fi
  fi
done <<< "$files"
bad_files=$(printf '%s\n' "$bad_files" | grep -v '^$' | sort -u || true)

# 추가된 행(+)만 본다. diff 헤더(+++ b/…)는 내용이 아니다.
hits=$("${diff_cmd[@]}" 2>/dev/null \
  | grep -E '^\+' | grep -Ev '^\+\+\+ ' \
  | grep -Ev "$ALLOW_RE" \
  | grep -Eic "$SECRET_RE" || true)

if [ -z "$bad_files" ] && [ "${hits:-0}" -eq 0 ]; then exit 0; fi

detail=""
[ -n "$bad_files" ] && detail="커밋되려는 비밀 파일:
$(printf '%s\n' "$bad_files" | sed 's/^/  - /')"
[ "${hits:-0}" -gt 0 ] && detail="$detail
커밋되려는 변경에서 비밀값 형태의 문자열 ${hits}건이 감지됐다. 확인: git diff --cached (또는 git diff HEAD)"

block "비밀값 커밋 시도" "$detail"
