#!/usr/bin/env bash
# PreToolUse(Bash) 훅 — 비밀값이 스테이징된 채 커밋되는 것을 막는다.
# CLAUDE.md 절대 규칙 5(비밀값)·S4 4부의 기계적 강제판.
# 발견한 값 자체는 출력하지 않는다. 파일·행 번호만 알린다.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
input=$(cat 2>/dev/null || true)

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -n "$cmd" ] || exit 0
printf '%s' "$cmd" | grep -Eq '(^|[;|&[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit' || exit 0
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0

staged=$(git -C "$ROOT" diff --cached --name-only 2>/dev/null || true)
[ -n "$staged" ] || exit 0

bad_files=$(printf '%s\n' "$staged" | grep -Ei '(^|/)\.env($|\.)|\.pem$|\.key$|(^|/)id_(rsa|dsa|ed25519)$|\.p12$|\.pfx$|(^|/)credentials\.json$|serviceAccount.*\.json$' | grep -v '\.env\.example$' || true)

hits=$(git -C "$ROOT" diff --cached -U0 2>/dev/null \
  | grep -nE '^\+' \
  | grep -Ev 'process\.env|os\.environ|getenv|ENV\[|<[A-Za-z_]+>|xxx|dummy|example|placeholder|your-|changeme|\.env\.example' \
  | grep -Eic 'AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)[[:space:]]*[:=][[:space:]]*.[A-Za-z0-9/+_-]{12,}' || true)

if [ -z "$bad_files" ] && [ "${hits:-0}" -eq 0 ]; then exit 0; fi

{
  echo "비밀값 커밋 시도 — 차단 (CLAUDE.md 절대 규칙 5 · S4 안정성)."
  echo
  [ -n "$bad_files" ] && { echo "스테이징된 비밀 파일:"; printf '%s\n' "$bad_files" | sed 's/^/  - /'; echo; }
  [ "${hits:-0}" -gt 0 ] && { echo "스테이징된 변경에서 비밀값 형태의 문자열 ${hits}건이 감지됐다."; echo "  확인: git diff --cached"; echo; }
  cat <<'MSG'
할 것:
  1. git restore --staged <파일> 로 스테이징에서 제외한다
  2. .gitignore에 해당 경로를 추가한다 (.env.example만 남긴다)
  3. 값은 환경 변수·비밀값 관리 도구로 옮기고 코드에서는 참조만 한다
  4. 이미 커밋·푸시된 적이 있으면 그 키를 폐기하고 재발급한다

오탐이면 docs/spec/code-conventions.md의 비밀값 검사 규칙에 예외를 기록한 뒤 진행하라.
MSG
} >&2
exit 2
