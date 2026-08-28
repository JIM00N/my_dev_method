#!/usr/bin/env bash
# 문서 참조 검사 — 문서가 가리키는 것이 실재하는지 확인한다.
# 통과 기준:
#  1)   백틱 참조 `docs/...` `.claude/...` `CLAUDE.md` `AGENTS.md` 가 templates/dev-kit 기준으로 존재
#  1-b) 키트 문서의 백틱 경로가 `docs/…` 관례를 지킴
#  1-c) **이 저장소 자신의 문서**(루트·`.claude/**`·`guides/**`)의 백틱 경로도 실재
#  2)   마크다운 링크 [..](상대경로) 가 각 파일 기준으로 존재
#  3)   훅·스크립트 실행 권한이 커밋되어 있음
#  4)   셸·파이썬·JSON 문법
#  5)   `파일.md` 「절 이름」 포인터의 절 이름이 그 파일에 실재
#  6)   report.py 가 하드코딩한 절 이름이 키트 양식에 실재
#  7)   `/mdm-kit-review` 축↔에이전트 표와 `.claude/agents/*.md` 실물이 일치
#  8)   (로컬 전용) issues.md 의 이슈 번호가 유일
#  9)   쓰기 도구를 가진 리뷰 에이전트에 임시 디렉토리 제한 문장이 있음
#  10)  이 저장소에서 밟은 셸 함정 재발 lint ($변수+멀티바이트 · awk 한글 ==)
#  11)  키트가 배포하는 `.claude/{commands,agents}/*.md` 의 파일명·`name:` 이 전부 `mdm-` 접두
# 1-c·5~11 은 `scripts/check-docs.py` 가 맡는다 (로케일·멀티바이트 안전).
# 붉어지는 증거는 `scripts/test-docs-check.sh` 에 있다 — 다만 **검사 1-c·5·6·7·8·9·10·11 까지**다.
# 검사 1·1-b·2·3·4 는 아직 증거가 없다(이슈 #159). 여기 '각 분기'라고 쓰지 않는다.
# 플레이스홀더(<n>, C<nn>, ST-<nnn>, ADR-<nnn>, *, 예시 경로)는 검사하지 않는다.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/templates/dev-kit"
fail=0

# 이 저장소 자신의 문서 목록 (키트 배포물 제외).
# `.gitignore` 된 로컬 전용 문서(issues.md·handoff-*.md)는 뺀다 — CI 에는 존재하지 않는 파일이라
# 여기서 잡으면 **로컬만 붉어지고 CI 는 조용한** 어긋난 검사가 된다 (1단계 == CI 원칙).
repo_docs() {
  local list
  list=$(find "$ROOT" -name '*.md' -not -path '*/.git/*' -not -path "$KIT/*" -not -path '*/manyfast_reference/*')
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$list" | git -C "$ROOT" check-ignore --stdin --non-matching --verbose 2>/dev/null \
      | sed -n 's/^::'$'\t''//p'
  else
    printf '%s\n' "$list"
  fi
}

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
  for py in "$KIT"/.claude/scripts/*.py "$ROOT"/scripts/*.py; do
    [ -e "$py" ] || continue
    python3 -c 'import sys;compile(open(sys.argv[1],encoding="utf-8").read(),sys.argv[1],"exec")' "$py" \
      || { echo "문법 오류: $py"; fail=1; }
  done
fi
if command -v jq >/dev/null 2>&1; then
  jq . "$KIT/.claude/settings.json" >/dev/null || { echo "settings.json 파싱 실패"; fail=1; }
fi

# 1-c · 5 · 6 · 7 · 8 · 9 · 10 은 파이썬이 맡는다.
# grep 부정 문자클래스가 C/POSIX 로케일에서 **바이트 클래스**가 되어 한글·em dash 안의 바이트에
# 걸리고, 그때 추출이 0건이 되면서 검사가 조용히 "통과"를 냈다 (이슈 #101). BSD awk 의 한글 `==`
# 버그(#098)도 같은 이유다. 파이썬은 인코딩을 명시적으로 다룬다.
# **python3 은 필수다** — 없으면 건너뛰지 않고 실패한다. 조용히 안 도는 검사는 없는 검사다.
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/scripts/check-docs.py" || fail=1
else
  echo "python3 가 없어 문서·에이전트·셸 검사(1-c·5~11)를 돌릴 수 없다"
  fail=1
fi

if [ "$fail" = 0 ]; then echo "문서 참조 검사 통과"; else exit 1; fi
