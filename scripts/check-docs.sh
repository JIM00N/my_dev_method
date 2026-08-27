#!/usr/bin/env bash
# 문서 참조 검사 — templates/dev-kit 안의 경로 참조가 실재하는지 확인한다.
# 통과 기준:
#  1) 백틱 참조 `docs/...` `.claude/...` `CLAUDE.md` `AGENTS.md` 가 templates/dev-kit 기준으로 존재
#  2) 마크다운 링크 [..](상대경로) 가 각 파일 기준으로 존재
# 플레이스홀더(<n>, C<nn>, ST-<nnn>, ADR-<nnn>, *, 예시 경로)는 검사하지 않는다.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/templates/dev-kit"
fail=0

is_placeholder() {
  case "$1" in
    *'<'*|*'*'*|*'…'*) return 0 ;;
    *C00-이름*|*ADR-000-'*'*) return 0 ;;
  esac
  # 번호 자리가 채워지지 않은 패턴 시리즈 참조
  printf '%s' "$1" | grep -Eq 'S[0-9]-\*|ST-[0-9_]*-\*|C[0-9_]*-\*|ADR-[0-9_]*-\*|-\*\.md' && return 0
  return 1
}

# 1) 백틱 참조 (키트 내부 문서 전체)
while IFS=: read -r file ref; do
  [ -n "$ref" ] || continue
  is_placeholder "$ref" && continue
  target="$KIT/$ref"
  if [ ! -e "$target" ]; then
    echo "깨진 참조: $file → \`$ref\`"
    fail=1
  fi
done < <(grep -rho --include='*.md' -E '`(docs|\.claude)/[A-Za-z0-9@_<>*./…-]+\.(md|sh|json|tsv)`' "$KIT" \
          | sed 's/`//g' | sort -u \
          | while IFS= read -r r; do
              grep -rl --include='*.md' -F "\`$r\`" "$KIT" | while IFS= read -r f; do
                echo "${f#"$ROOT"/}:$r"
              done
            done)

# 1-b) 경로 관례 위반 — 키트 문서의 백틱 참조는 프로젝트 루트 기준 docs/… 하나로 통일한다
while IFS=: read -r file line ref; do
  [ -n "$ref" ] || continue
  echo "경로 관례 위반(docs/ 접두어 없음): ${file#"$ROOT"/}:$line → $ref"
  fail=1
done < <(grep -rno --include='*.md' -E '\`((guides|spec|plan|quality|status|decisions|addons|upstream)/[A-Za-z0-9@_<>*./…-]+\.(md|sh|json)|\.\./[A-Za-z0-9@_<>*./…-]+)\`' "$KIT" || true)

# 2) 마크다운 링크 (저장소 전체, http 제외)
while IFS= read -r file; do
  dir=$(dirname "$file")
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    case "$link" in http*|'#'*|mailto:*) continue ;; esac
    is_placeholder "$link" && continue
    tgt="${link%%#*}"
    if [ ! -e "$dir/$tgt" ] && [ ! -e "$ROOT/$tgt" ]; then
      echo "깨진 링크: ${file#"$ROOT"/} → ($link)"
      fail=1
    fi
  done < <(grep -oE '\]\(([^)]+)\)' "$file" | sed -E 's/^\]\(//; s/\)$//')
done < <(find "$ROOT" -name '*.md' -not -path '*/.git/*')

# 3) 훅 실행 권한이 커밋되어 있는지
while IFS= read -r mode_path; do
  mode=${mode_path%% *}
  if [ "$mode" != "100755" ]; then
    echo "실행 권한 없는 훅: $mode_path"
    fail=1
  fi
done < <(cd "$ROOT" && git ls-files -s \
          'templates/dev-kit/.claude/hooks/*.sh' 'templates/dev-kit/.claude/scripts/*.sh' 'templates/dev-kit/.claude/scripts/*.py' \
          '.githooks/*' '.claude/scripts/*.sh' 'scripts/*.sh' 2>/dev/null | awk '{print $1" "$4}')
# ↑ `.githooks/*` 를 반드시 포함한다: git 은 실행 권한 없는 훅을 **오류 없이 조용히 건너뛴다.**
#   모드가 100644 로 커밋되면 커밋 게이트 전체가 fail-open 이 되는데, 회귀 fixture 는 임시 사본에
#   chmod +x 를 걸고 돌리므로 그 회귀를 못 잡는다. 이 검사가 유일한 그물이다.

# 4) 훅·스크립트·설정 문법 (배포물 + 이 저장소 자신의 게이트·스크립트)
for sh in "$KIT"/.claude/hooks/*.sh "$KIT"/.claude/scripts/*.sh \
          "$ROOT"/.githooks/* "$ROOT"/.claude/scripts/*.sh "$ROOT"/scripts/*.sh; do
  [ -f "$sh" ] || continue
  bash -n "$sh" || { echo "문법 오류: $sh"; fail=1; }
done
# .py 는 py_compile 대신 compile() 로 본다 — __pycache__ 를 남기지 않기 위해서다
if command -v python3 >/dev/null 2>&1; then
  for py in "$KIT"/.claude/scripts/*.py; do
    [ -e "$py" ] || continue
    python3 -c 'import sys;compile(open(sys.argv[1],encoding="utf-8").read(),sys.argv[1],"exec")' "$py" \
      || { echo "문법 오류: $py"; fail=1; }
  done
fi
if command -v jq >/dev/null 2>&1; then
  jq . "$KIT/.claude/settings.json" >/dev/null || { echo "settings.json 파싱 실패"; fail=1; }
fi

if [ "$fail" = 0 ]; then echo "문서 참조 검사 통과"; else exit 1; fi
