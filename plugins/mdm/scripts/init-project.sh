#!/usr/bin/env bash
# dev-kit 제품 저장소 초기화·업그레이드 — `mdm init` (`/mdm:init` 커맨드가 부른다)
#
#   mdm init <제품 저장소 경로>                              신규 설치
#   mdm init <제품 저장소 경로> --upgrade                    업그레이드 (키트 소유 문서만 교체)
#   mdm init <제품 저장소 경로> --upgrade --retire-legacy    + 1.x 배포본이 복사해 둔 .claude/ 키트 파일 중
#                                                            **원본과 바이트 단위로 같은 것만** 물린다
#
# 2.0.0 부터 커맨드·서브에이전트·훅·검사 엔진은 **플러그인이 제공**하고 제품에 복사하지 않는다.
# 제품에 심는 것은 다섯 가지다 — CLAUDE.md · AGENTS.md · docs/ · .github/workflows/mdm-check.yml(없을 때만) ·
# .gitignore 줄 — 그리고 .claude/settings.json 에 플러그인을 **프로젝트 범위로 등록**한다(팀 전체가 같은 판을 받는다).
#
# 소유권 규칙 (plugins/mdm/README.md 의 표가 정본):
#   - 키트 소유 문서(guides·템플릿·대부분의 index)만 교체한다.
#   - 프로젝트 소유 파일(spec 내용·plan·quality 기록·STATUS·ADR·meta·evidence)은 절대 덮어쓰지 않는다.
#   - **index 라고 다 키트 소유는 아니다**: `docs/plan/index.md`·`docs/decisions/index.md` 는
#     프로젝트 데이터(사이클 현황 행·ADR 목록 행)가 실려 0.7.0 에서 프로젝트 소유로 내려왔다.
#   - 1.x 가 남긴 `.claude/` 키트 파일은 **기본으로 건드리지 않는다.** 찾아서 분류(원본과 동일/변경됨)해 알린다.
#     `--retire-legacy` 를 줬을 때만, 그것도 해시가 원본과 같은 파일만 개칭한다 — 「이 파일이 키트 것인가」를
#     추측한 자동 이관 두 판을 리뷰가 둘 다 치명으로 잡아 걷어냈기 때문이다(1판은 프로젝트 파일을 지웠고, 2판은 가드가 실제 경로에서 닫히지 않았다)(2026-08-27 사용자 결정). 내용 해시는 추측이 아니다.
set -uo pipefail

usage() {
  cat <<'USAGE'
사용법: mdm init <제품 저장소 경로> [--upgrade] [--retire-legacy]

  (기본)           처음 적용하는 저장소에 문서 골격을 심는다. CLAUDE.md·docs/가 이미 있으면 중단한다.
  --upgrade        이미 키트를 쓰는 저장소에서 키트 소유 문서만 새 판으로 교체한다.
  --retire-legacy  (--upgrade 와 함께) 1.x 가 복사해 둔 .claude/ 키트 파일 중 원본과 같은 것만
                   *.dev-kit-1x-retired 로 물리고 그 훅의 settings.json 등록을 뺀다.
USAGE
}

die() { echo "오류: $*" >&2; exit 1; }
note() { echo "  $*"; }

PLUGIN="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || die "플러그인 루트를 찾을 수 없다"
SRC="$PLUGIN/templates"
[ -d "$SRC" ] || die "플러그인에 templates/ 가 없다 ($SRC) — 플러그인 설치가 깨졌다"
MANIFEST="${MDM_LEGACY_MANIFEST:-$PLUGIN/scripts/legacy-manifest.tsv}"
MARKET="my-dev-method"; MARKET_REPO="JIM00N/my_dev_method"; PLUGIN_ID="mdm@$MARKET"

TARGET=""; MODE="install"; RETIRE=0
for arg in "$@"; do
  case "$arg" in
    --upgrade) MODE="upgrade" ;;
    --retire-legacy) RETIRE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; die "알 수 없는 옵션: $arg" ;;
    *) [ -z "$TARGET" ] || die "대상 경로는 하나만 받는다"; TARGET="$arg" ;;
  esac
done
[ -n "$TARGET" ] || { usage; exit 1; }
[ "$RETIRE" = 0 ] || [ "$MODE" = upgrade ] || die "--retire-legacy 는 --upgrade 와 함께 쓴다"
[ -d "$TARGET" ] || die "대상 디렉터리가 없다: $TARGET (먼저 mkdir + git init)"
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" != "$PLUGIN" ] && [ "$TARGET" != "$(cd "$PLUGIN/../.." 2>/dev/null && pwd)" ] \
  || die "방법론 저장소(플러그인) 자신에는 설치하지 않는다"

command -v python3 >/dev/null 2>&1 || die "python3 가 필요하다 (계약·계획 검사 · settings.json 등록)"
# 1.x 잔재 판별 매니페스트는 플러그인과 함께 온다. 없으면 잔재를 전부 「이 저장소 것」으로 조용히 분류해
# 「찾아서 알린다」가 꺼진다 — 그 상태로 진행하지 않는다 (issues #443).
[ -f "$MANIFEST" ] || die "1.x 잔재 판별 매니페스트가 없다: $MANIFEST (플러그인 설치가 깨졌다 — /plugin 에서 mdm 을 다시 설치한다)"

KIT_VER=$(sed -n '1s/.*dev-kit v\([0-9.]*\).*/\1/p' "$SRC/CLAUDE.md")
PLUGIN_VER=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("version",""))' "$PLUGIN/.claude-plugin/plugin.json" 2>/dev/null || true)
[ -n "$KIT_VER" ] && [ "$KIT_VER" = "$PLUGIN_VER" ] \
  || die "CLAUDE.md 스탬프(v${KIT_VER:-?})와 plugin.json version(${PLUGIN_VER:-?})이 다르다 — 배포본이 깨졌다"
echo "dev-kit v${KIT_VER} (플러그인 $PLUGIN_ID) → $TARGET (${MODE})"
echo

# ---------- 사전 점검 ----------
if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  note "⚠ 대상이 git 저장소가 아니다. 훅(비밀값·STATUS)과 인계 검사는 git 저장소에서만 온전히 동작한다 — git init을 먼저 권한다."
else
  if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ]; then
    note "⚠ 대상 작업 트리에 커밋되지 않은 변경이 있다. 설치 후 git diff로 확인할 수 있게 먼저 커밋해 두는 것을 권한다."
  fi
fi
command -v jq >/dev/null 2>&1 || note "⚠ jq가 없다. guard 훅 2개는 jq 없이는 경고만 남기고 통과한다 — brew install jq"
echo

# 파일 하나 복사: 대상이 이미 있고 내용이 다르면 표시
copy_file() { # $1 = templates 기준 상대 경로
  local rel="$1" from="$SRC/$1" to="$TARGET/$1"
  mkdir -p "$(dirname "$to")"
  if [ -e "$to" ] && ! cmp -s "$from" "$to"; then
    cp "$from" "$to" || die "복사 실패: $rel"; note "교체: $rel"
  elif [ -e "$to" ]; then
    : # 동일 — 조용히 넘어간다
  else
    cp "$from" "$to" || die "복사 실패: $rel"; note "생성: $rel"
  fi
}

copy_if_absent() { # $1 = templates 기준 상대 경로. 이미 있으면 손대지 않는다.
  local rel="$1" to="$TARGET/$1"
  if [ -e "$to" ]; then return 0; fi
  mkdir -p "$(dirname "$to")"
  cp "$SRC/$rel" "$to" || die "복사 실패: $rel"; note "생성: $rel (양식 — 이후 프로젝트가 소유한다)"
}

# 업그레이드에서 교체하는 키트 소유 파일 (README 소유권 표와 일치해야 한다)
KIT_OWNED="
docs/index.md
docs/MOC.md
docs/upstream/index.md
docs/spec/index.md
docs/plan/archive/index.md
docs/plan/cycles/C00-template.md
docs/plan/stories/ST-000-template.md
docs/quality/index.md
docs/quality/archive/index.md
docs/status/index.md
docs/status/archive/index.md
docs/decisions/ADR-000-template.md
AGENTS.md
"

# "프로젝트가 채우는" 양식 — 없을 때만 넣고, 있으면 절대 건드리지 않는다.
# `docs/plan/index.md`·`docs/decisions/index.md` 는 사이클 현황 행·ADR 목록 행(프로젝트 데이터)이 실리는 자리라
# 0.7.0 에서 KIT_OWNED 에서 내려왔다 — 양식으로 통째 교체하면 행이 사라지고 검사 I 가 그것을 사용자 과실처럼 보고한다.
KIT_SEED="
docs/plan/index.md
docs/decisions/index.md
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
  for line in 'docs/reports/'; do
    if [ -f "$gi" ] && grep -qxF "$line" "$gi"; then continue; fi
    if [ ! -f "$gi" ]; then
      printf '# dev-kit 생성물 — 정본은 docs/ 의 md 다\n' > "$gi" || die ".gitignore 를 쓸 수 없다: $gi"
    elif ! grep -q 'dev-kit 생성물' "$gi"; then
      printf '\n# dev-kit 생성물 — 정본은 docs/ 의 md 다\n' >> "$gi" || die ".gitignore 를 쓸 수 없다: $gi"
    fi
    printf '%s\n' "$line" >> "$gi" || die ".gitignore 를 쓸 수 없다: $gi"
    note "gitignore 추가: $line"
  done
}

# .claude/settings.json 에 플러그인을 프로젝트 범위로 등록한다. 다른 키·항목은 건드리지 않는다.
# 이미 다른 값이 있으면 덮지 않고 알린다 — 프로젝트가 정한 것이다.
register_plugin() {
  local settings="$TARGET/.claude/settings.json" out
  mkdir -p "$TARGET/.claude"
  out=$(python3 - "$settings" "$MARKET" "$MARKET_REPO" "$PLUGIN_ID" 2>&1 <<'PY'
import json, os, sys
p, mk, repo, plugin = sys.argv[1:5]
obj = {}
if os.path.exists(p):
    try:
        with open(p, encoding='utf-8') as f:
            obj = json.load(f)
    except ValueError as e:
        sys.exit('settings.json 을 읽을 수 없다 (JSON 오류) — 손으로 고친 뒤 다시 실행한다: %s' % e)
    if not isinstance(obj, dict):
        sys.exit('settings.json 최상위가 객체가 아니다')
changed, warn = [], []
want = {'source': {'source': 'github', 'repo': repo}}
for key in ('extraKnownMarketplaces', 'enabledPlugins'):
    if key in obj and not isinstance(obj[key], dict):
        sys.exit('settings.json 의 %s 가 객체가 아니다(%s) — 이 저장소가 정한 값이라 덮지 않는다. 손으로 고친 뒤 다시 실행한다' % (key, type(obj[key]).__name__))
mks = obj.setdefault('extraKnownMarketplaces', {})
if mk not in mks:
    mks[mk] = want; changed.append('extraKnownMarketplaces.' + mk)
elif mks[mk] != want:
    warn.append('extraKnownMarketplaces.%s 가 이미 있고 값이 다르다 — 건드리지 않았다 (프로젝트가 정한 출처)' % mk)
eps = obj.setdefault('enabledPlugins', {})
if eps.get(plugin) is True:
    pass
elif plugin in eps:
    warn.append('enabledPlugins.%s 가 꺼져 있다 — 켜지 않았다 (프로젝트가 껐다)' % plugin)
else:
    eps[plugin] = True; changed.append('enabledPlugins.' + plugin)
if changed:
    p = os.path.realpath(p)   # 심볼릭 링크면 링크를 지키고 대상 파일에 쓴다 (issues #451)
    tmp = p + '.mdm-tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2); f.write('\n')
    os.replace(tmp, p)
for c in changed: print('등록: ' + c)
for w in warn: print('⚠ ' + w)
PY
  ) || die "$out"
  [ -z "$out" ] && note "플러그인 등록: 이미 되어 있다 (.claude/settings.json)" || printf '%s\n' "$out" | sed 's/^/  /'
}

# ---------- 1.x(복사 방식) 잔재 분류 ----------
# 1.x 배포본은 커맨드·에이전트·훅·스크립트를 제품의 .claude/ 에 복사했다. 그 파일이 남아 있으면
# 플러그인의 /mdm:adopt 와 옛 /mdm-adopt 가 함께 뜨고, 옛 훅이 옛 엔진 경로로 두 번 돈다.
# 「이 파일이 키트 것인가」는 **내용 해시**로만 판정한다 — legacy-manifest.tsv(원본 각 판의 sha256)와 같으면 키트 것이다.
LEGACY_HOOK_RE='(^|/)\.claude/hooks/(guard-dependency|guard-secrets|status-updated)\.sh$'
sha_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

legacy_files() { # 제품의 .claude/ 아래에서 매니페스트에 경로가 있는 파일만 (경로 기준 상대)
  local f rel
  [ -d "$TARGET/.claude" ] || return 0
  ( cd "$TARGET" && find .claude -type f \( -path '.claude/commands/*' -o -path '.claude/agents/*' -o -path '.claude/hooks/*' -o -path '.claude/scripts/*' -o -name 'README.md' -o -name 'settings.json.dev-kit' \) 2>/dev/null ) \
  | sed 's#^\./##' | sort
}

manifest_lookup() { # $1 rel  $2 sha → 버전 문자열 (없으면 빈 문자열). 경로가 매니페스트에 없으면 rc 2.
  local rel="$1" sha="$2" key="$1"
  [ "$rel" = ".claude/settings.json.dev-kit" ] && key=".claude/settings.json"
  [ -f "$MANIFEST" ] || return 2
  grep -q "^${key}	" "$MANIFEST" || return 2
  awk -F'\t' -v k="$key" -v h="$sha" '$1 == k && $3 == h { print $2; exit }' "$MANIFEST"
}

LEGACY_SAME=""; LEGACY_DIFF=""
classify_legacy() {
  local rel sha ver rc
  LEGACY_SAME=""; LEGACY_DIFF=""
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$TARGET/$rel" ] || continue
    sha=$(sha_of "$TARGET/$rel")
    ver=$(manifest_lookup "$rel" "$sha"); rc=$?
    [ "$rc" = 2 ] && continue            # 키트가 그 이름을 쓴 적이 없다 — 이 저장소 것
    if [ -n "$ver" ]; then LEGACY_SAME="$LEGACY_SAME
$rel	$ver"; else LEGACY_DIFF="$LEGACY_DIFF
$rel"; fi
  done < <(legacy_files)
  LEGACY_SAME=$(printf '%s\n' "$LEGACY_SAME" | sed '/^$/d'); LEGACY_DIFF=$(printf '%s\n' "$LEGACY_DIFF" | sed '/^$/d')
}

legacy_hook_registrations() { # settings.json 에 남은 1.x 훅 등록 수
  local s="$TARGET/.claude/settings.json"
  [ -f "$s" ] || { echo 0; return; }
  python3 - "$s" "$LEGACY_HOOK_RE" <<'PY' 2>/dev/null || echo 0
import json, re, sys
try:
    obj = json.load(open(sys.argv[1], encoding='utf-8'))
except ValueError:
    print(0); sys.exit()
rx = re.compile(sys.argv[2])
n = 0
for event, groups in (obj.get('hooks') or {}).items():
    for g in groups or []:
        for h in (g.get('hooks') or []):
            if rx.search(str(h.get('command', ''))):
                n += 1
print(n)
PY
}

report_legacy() {
  classify_legacy
  local n_reg; n_reg=$(legacy_hook_registrations)
  [ -n "$LEGACY_SAME$LEGACY_DIFF" ] || [ "$n_reg" != 0 ] || return 0
  echo
  note "⚠ 1.x(복사 방식) 배포본이 남긴 .claude/ 키트 파일이 있다 — 2.0.0 부터 이 파일들은 플러그인이 제공한다."
  note "  둘 다 살아 있으면 /mdm-adopt(옛) 와 /mdm:adopt(새) 가 함께 뜨고, 옛 훅이 옛 엔진으로 한 번 더 돈다."
  if [ -n "$LEGACY_SAME" ]; then
    note "  원본과 바이트 단위로 같은 파일 (키트 것이 확실하다 — --retire-legacy 가 물릴 수 있는 것):"
    printf '%s\n' "$LEGACY_SAME" | awk -F'\t' '{ printf "    - %s  (dev-kit %s)\n", $1, $2 }'
  fi
  if [ -n "$LEGACY_DIFF" ]; then
    note "  키트의 옛 이름이지만 내용이 다른 파일 (이 저장소가 고쳤거나 이 저장소 것이다 — **어느 경우에도 건드리지 않는다**):"
    printf '%s\n' "$LEGACY_DIFF" | sed 's/^/    - /'
    note "    파일을 열어 판단한 뒤 사람이 처리한다 (플러그인 README 「1.x 에서 올라오기」)."
  fi
  [ "$n_reg" != 0 ] && note "  .claude/settings.json 에 1.x 훅 등록 ${n_reg}건이 남아 있다 (\$CLAUDE_PROJECT_DIR/.claude/hooks/…)."
  if [ "$RETIRE" = 1 ]; then
    retire_legacy
  else
    note "  **이 실행은 아무것도 건드리지 않았다.** 위 「같은 파일」만 물리려면: mdm init $TARGET --upgrade --retire-legacy"
  fi
}

retire_legacy() {
  local rel ver retired=""
  [ -n "$LEGACY_SAME" ] || { note "  물릴 것이 없다 (원본과 같은 파일이 없다)."; }
  while IFS=$'\t' read -r rel ver; do
    [ -n "$rel" ] || continue
    mv "$TARGET/$rel" "$TARGET/$rel.dev-kit-1x-retired" || die "개칭 실패: $rel"
    note "  물림: $rel → $rel.dev-kit-1x-retired (dev-kit $ver 원본과 동일)"
    retired="$retired
$rel"
  done <<< "$LEGACY_SAME"
  # 물린 훅 파일의 등록만 뺀다 — 파일이 남아 있는(변경된) 훅의 등록은 그대로 둔다.
  local s="$TARGET/.claude/settings.json"
  [ -f "$s" ] || return 0
  python3 - "$s" "$LEGACY_HOOK_RE" "$retired" <<'PY' || die "settings.json 훅 등록 정리 실패"
import json, os, re, sys
p, pattern, retired = sys.argv[1], sys.argv[2], set(l for l in sys.argv[3].split('\n') if l)
obj = json.load(open(p, encoding='utf-8'))
rx = re.compile(pattern)
removed = 0
hooks = obj.get('hooks') or {}
for event in list(hooks):
    groups = hooks[event] or []
    kept_groups = []
    for g in groups:
        kept = []
        for h in (g.get('hooks') or []):
            cmd = str(h.get('command', ''))
            m = rx.search(cmd)
            if m and ('.claude/hooks/%s.sh' % m.group(2)) in retired:
                removed += 1
                continue
            kept.append(h)
        if kept:
            g['hooks'] = kept; kept_groups.append(g)
    if kept_groups:
        hooks[event] = kept_groups
    else:
        del hooks[event]
if removed:
    if not hooks:
        obj.pop('hooks', None)
    p = os.path.realpath(p)   # 심볼릭 링크면 링크를 지키고 대상 파일에 쓴다 (issues #451)
    tmp = p + '.mdm-tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2); f.write('\n')
    os.replace(tmp, p)
print('  settings.json 훅 등록 %d건 제거 (물린 훅 파일의 것만)' % removed)
PY
}

# 제품 CI — 양식은 없을 때만 심는다(프로젝트 소유). 이미 있는데 MDM_KIT_REF 핀이 없으면 1.x 양식이거나
# 이 저장소가 직접 쓴 CI 다. 올릴 핀이 없으므로 2.0.0 양식을 사이드카로 두고 교체를 안내한다 (issues #427).
# 1.x 양식은 옛 엔진 경로(.claude/scripts/)를 부르므로 --retire-legacy 로 옛 파일을 물리는 순간 깨진다 — 그것도 알린다.
check_ci() {
  local ci="$TARGET/.github/workflows/mdm-check.yml"
  [ -f "$ci" ] || return 0
  grep -q 'MDM_KIT_REF' "$ci" && return 0
  cp "$SRC/.github/workflows/mdm-check.yml" "$ci.dev-kit-new" || die "복사 실패: .github/workflows/mdm-check.yml.dev-kit-new"
  note "⚠ .github/workflows/mdm-check.yml 에 MDM_KIT_REF 가 없다 — 1.x 양식이거나 이 저장소가 직접 쓴 CI 다. 덮어쓰지 않았다."
  note "  2.0.0 양식을 .github/workflows/mdm-check.yml.dev-kit-new 로 두었다. 그 파일로 교체하고(이 저장소가 더한 단계는 옮겨 적는다) 사이드카를 지운다."
  if grep -q '\.claude/scripts/' "$ci"; then
    note "  이 CI 는 옛 엔진 경로 .claude/scripts/ 를 부른다 — 교체 전에 --retire-legacy 로 옛 파일을 물리면 CI 가 그 순간 깨진다."
  fi
}

if [ "$MODE" = "install" ]; then
  # ---------- 신규 설치 ----------
  for e in CLAUDE.md docs; do
    [ ! -e "$TARGET/$e" ] || die "$e 가 이미 있다. 키트를 쓰던 저장소면 --upgrade 를 쓴다 — 키트를 쓴 적 없는 저장소면 쓰지 않는다 (--upgrade 는 docs/index.md·docs/MOC.md·AGENTS.md 등을 키트 판으로 교체한다)."
  done
  ensure_gitignore      # 쓰기가 실패할 수 있는 것부터 — 실패하면 문서를 심기 전에 멈춘다
  register_plugin
  cp "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md" || die "복사 실패: CLAUDE.md";  note "생성: CLAUDE.md"
  cp "$SRC/AGENTS.md" "$TARGET/AGENTS.md" || die "복사 실패: AGENTS.md";  note "생성: AGENTS.md"
  cp -R "$SRC/docs" "$TARGET/docs" || die "복사 실패: docs/";              note "생성: docs/ 전체"
  copy_if_absent ".github/workflows/mdm-check.yml"
  check_ci
  report_legacy
  cat <<NEXT

설치 완료 (dev-kit v${KIT_VER}). 이어서 할 일:
  1. CLAUDE.md 상단 첫 두 줄(제목·한 줄 설명)을 프로젝트 것으로 바꾼다
  2. docs/status/STATUS.md에 시작 시점 기록
  3. (업무 자동화·AX 프로젝트면) docs/guides/addons/business-automation.md 확인 (CLAUDE.md 라우팅 표에 연결돼 있다)
  4. .claude/settings.json 에 플러그인 ${PLUGIN_ID} 를 프로젝트 범위로 등록했다 — **Claude Code 를 다시 시작**하면
       설치를 묻는다. 묻지 않으면: /plugin marketplace add ${MARKET_REPO} → /plugin install ${PLUGIN_ID}
       확인: /hooks 에 훅 3개(status-updated · guard-dependency · guard-secrets), /help 에 /mdm:… 커맨드
  5. /mdm:adopt 를 실행한다 (현재 단계 S0) — 진입점은 하나다.
       (제품 CI(.github/workflows/mdm-check.yml)는 도입 — mdm contract adopt — 전에는 붉다. 그 실패가 정상이다)
       저장소 안의 계획 문서를 먼저 찾고, 없으면 밖에 있는지 묻고,
       그래도 없으면 /mdm:plan 으로 보내 키트가 직접 만든다
NEXT
else
  # ---------- 업그레이드 ----------
  [ -e "$TARGET/CLAUDE.md" ] || die "CLAUDE.md가 없다. 키트가 없는 저장소다 — --upgrade 없이 실행해라."
  CUR_VER=$(sed -n '1s/.*dev-kit v\([0-9.]*\).*/\1/p' "$TARGET/CLAUDE.md")
  echo "현재 배포본: v${CUR_VER:-스탬프 없음(0.2.0 이전)} → v${KIT_VER}"
  echo "키트 소유 문서만 교체한다. 프로젝트 소유 파일(spec 내용·plan·quality 기록·STATUS·ADR·meta·evidence)은 건드리지 않는다."
  echo
  ensure_gitignore
  register_plugin
  # 파이프라인으로 돌리면 while 이 서브셸이라 copy_file 의 die 가 서브셸만 끝낸다 — 「오류: 복사 실패」 뒤에
  # 「업그레이드 완료」·rc 0 이 나오고 find 순서상 뒤의 가이드가 전부 옛 판으로 남았다 (issues #429 · #171 계열).
  while IFS= read -r rel; do
    copy_file "$rel"
  done < <(cd "$SRC" && find docs/guides -type f -name '*.md' | sort)
  for rel in $KIT_OWNED; do copy_file "$rel"; done
  for rel in $KIT_SEED; do copy_if_absent "$rel"; done
  note "보존됨: docs/plan/index.md · docs/decisions/index.md (프로젝트 데이터가 실리는 표 — 양식 변경은 CHANGELOG 확인)"
  copy_if_absent ".github/workflows/mdm-check.yml"
  check_ci
  # CLAUDE.md는 프로젝트명·§6 고유 규칙이 있어 자동 교체하지 않는다
  if ! cmp -s "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md"; then
    cp "$SRC/CLAUDE.md" "$TARGET/CLAUDE.md.dev-kit-new" || die "복사 실패: CLAUDE.md.dev-kit-new"
    note "⚠ CLAUDE.md는 자동 교체하지 않았다 (프로젝트명·§6 고유 규칙 보존)."
    note "  새 판을 CLAUDE.md.dev-kit-new 로 두었다. **새 판으로 교체한 뒤 프로젝트명과 §6 고유 규칙만 되살려라**"
    note "  (라우팅 표·절대 규칙이 바뀌었을 수 있다 — '규칙 부분만' 옮기면 §1 라우팅 표 변경을 놓친다)."
  fi
  report_legacy
  cat <<NEXT

업그레이드 완료 (v${CUR_VER:-스탬프 없음} → v${KIT_VER}). 이어서 할 일:
  1. git diff로 교체된 키트 문서를 확인한다
  2. CLAUDE.md.dev-kit-new 가 있으면 병합 후 삭제 (첫 줄 버전 스탬프를 v${KIT_VER}로)
  3. **원본 저장소**(my_dev_method)의 CHANGELOG.md 에서 v${CUR_VER:-이전} 이후 항목을 읽고,
       "양식 변경"이 명시된 프로젝트 소유 파일이 있으면 내용을 새 양식으로 옮겨 적는다
       (키트는 CHANGELOG 를 배포하지 않는다 — 원본 저장소에서 읽어야 한다)
  4. CI: .github/workflows/mdm-check.yml 에 MDM_KIT_REF 가 있으면 그 핀을 v${KIT_VER} 로 올린다.
       없으면(1.x 양식) 위 ⚠ 대로 mdm-check.yml.dev-kit-new 로 교체한다 — 'mdm doctor' 의 ci_pin_matches·ci_legacy 가 대조한다
  5. docs/status/STATUS.md 최근 결정에 업그레이드 사실 한 줄
  6. **세션을 다시 시작한다** — 플러그인 등록·커맨드 목록은 세션 시작 시점에 읽힌다.
       위에 ⚠ 로 알린 1.x 잔재가 있으면 플러그인 README 「1.x 에서 올라오기」를 따른다
NEXT
fi

note "진단: mdm doctor (원격 CI 활성화는 --github 로 별도 조회)"
cat <<'EVIDENCE'
계약 근거 검사:
  docs/guides/contract-evidence.md를 읽고 mdm contract adopt 를 실행한다.
  기존 준비·완료 표시는 새 증거로 자동 승계되지 않는다.
  도입 전 계획 작성만 mdm check --init 을 사용한다 (운영 통과 아님).
  docs/meta/와 docs/evidence/는 프로젝트 소유이며 업그레이드가 덮어쓰지 않는다.
EVIDENCE
