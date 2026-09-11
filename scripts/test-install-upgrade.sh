#!/usr/bin/env bash
# init-project.sh(`mdm init`) 설치·업그레이드 회귀 검사 — 임시 저장소에 **실제로 돌려서** 본다.
#
# 2.0.0(플러그인 전환) 이 겨냥하는 것:
#   1) 신규 설치가 제품에 **문서 골격과 플러그인 등록만** 심는다 — .claude/{commands,agents,hooks,scripts} 를 복사하지 않는다.
#   2) 기존 .claude/settings.json 의 다른 키·다른 플러그인 등록을 보존한 채 두 키만 더한다. 깨진 JSON 은 건드리지 않고 실패한다.
#   3) 1.x 잔재(제품에 복사돼 있던 키트 .claude/ 파일)는 **내용 해시**로만 분류한다 —
#      원본과 같은 것은 「같음」, 이름만 같고 내용이 다른 것은 「다름」, 키트가 쓴 적 없는 이름은 무시(이 저장소 것).
#      기본은 **불간섭**(찾아서 알리기만). --retire-legacy 를 줘도 「같음」만 개칭하고 「다름」은 어느 경우에도 건드리지 않는다.
#      (0.7.0 개명 때 「키트 것인가」를 추측한 자동 이관 두 판을 리뷰가 둘 다 치명으로 잡아 걷어냈기 때문이다(1판은 프로젝트 파일을 지웠고, 2판은 가드가 실제 경로에서 닫히지 않았다) — 2026-08-27 사용자 결정.
#       해시는 추측이 아니지만 그 결정을 뒤집는 것은 사용자 몫이라 옵트인이다.)
#   4) 업그레이드가 키트 소유 문서는 갈고, 프로젝트 소유(카탈로그 행·증거·CI 워크플로·source-map)는 보존한다.
#   5) 배포본 무결성 — templates/CLAUDE.md 스탬프 ≠ plugin.json version 이면 설치기가 죽는다.
#
# 분류 근거(legacy-manifest.tsv)는 MDM_LEGACY_MANIFEST 로 **합성본**을 넘긴다 — 실제 1.x 파일 바이트가 없어도
# 「해시가 같다/다르다」의 분기를 잰다. 배포되는 실물 매니페스트는 별도로 형식·포함 항목을 단언한다.
# 마지막 뮤테이션 자기검증은 해시 대조를 끄면 「다름」이 개칭되는 것을 보여 fixture 가 진짜로 그 분기를 재고 있음을 못박는다.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="$ROOT/plugins/mdm"
INIT="$PLUGIN/scripts/init-project.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
ok() { printf '  통과  %s\n' "$*"; }
ng() { printf '  실패  %s\n' "$*"; fail=1; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
PLUGIN_VER=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")

fresh() { local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q; printf '%s' "$d"; }
run_init() { bash "$INIT" "$@" > "$TMP/out" 2>&1; RC=$?; }

echo "1. 신규 설치 — 문서 골격과 플러그인 등록만"
d=$(fresh fx1); run_init "$d"
[ "$RC" = 0 ] && ok "신규 설치 rc=0" || { ng "신규 설치 rc=$RC"; sed 's/^/      /' "$TMP/out" | tail -5; }
for f in CLAUDE.md AGENTS.md docs/index.md docs/guides/S0-adopt.md docs/status/STATUS.md .github/workflows/mdm-check.yml .claude/settings.json; do
  [ -f "$d/$f" ] || ng "신규 설치가 $f 를 만들지 않았다"
done
ok "신규 설치가 CLAUDE.md·AGENTS.md·docs/·CI 양식·settings.json 을 만든다 (빠진 것은 위에 실패로 찍힌다)"
copied=$(cd "$d" && ls -d .claude/commands .claude/agents .claude/hooks .claude/scripts .claude/README.md 2>/dev/null | tr '\n' ' ')
[ -z "$copied" ] && ok "**.claude/ 에 키트 파일을 복사하지 않는다** (플러그인이 제공한다)" \
  || ng "신규 설치가 1.x 처럼 .claude/ 키트 파일을 복사했다: $copied"
python3 - "$d/.claude/settings.json" <<'PY' && ok "settings.json 에 마켓플레이스·플러그인 등록 두 키가 들어간다" || ng "settings.json 등록이 빠졌거나 형식이 다르다"
import json, sys
o = json.load(open(sys.argv[1]))
assert o['extraKnownMarketplaces']['my-dev-method']['source'] == {'source': 'github', 'repo': 'JIM00N/my_dev_method'}
assert o['enabledPlugins']['mdm@my-dev-method'] is True
PY
grep -q "dev-kit v${PLUGIN_VER} " "$d/CLAUDE.md" && ok "심은 CLAUDE.md 스탬프가 플러그인 버전(${PLUGIN_VER})이다" || ng "CLAUDE.md 스탬프가 플러그인 버전과 다르다"
grep -q "MDM_KIT_REF: v${PLUGIN_VER}" "$d/.github/workflows/mdm-check.yml" && ok "심은 CI 양식의 핀이 플러그인 버전이다" || ng "CI 양식의 MDM_KIT_REF 핀이 플러그인 버전과 다르다"
grep -q '/mdm:adopt' "$TMP/out" && ok "다음 행동으로 /mdm:adopt 를 안내한다" || ng "설치 출력이 다음 행동(/mdm:adopt)을 말하지 않는다"
grep -qxF 'docs/reports/' "$d/.gitignore" && ok ".gitignore 에 docs/reports/ 를 넣는다" || ng ".gitignore 에 docs/reports/ 가 없다"
run_init "$d"
[ "$RC" != 0 ] && grep -q -- '--upgrade' "$TMP/out" && ok "이미 설치된 곳에 다시 설치하면 중단하고 --upgrade 를 안내한다" || ng "재설치를 막지 않았다 (rc=$RC)"
run_init "$d" --upgrade
[ ! -e "$d/.github/workflows/mdm-check.yml.dev-kit-new" ] && ok "핀이 있는 CI(2.0.0 양식)에는 사이드카를 남기지 않는다" || ng "핀이 이미 있는데 CI 사이드카를 남겼다"

echo
echo "2. 기존 settings.json 보존"
d=$(fresh fx2); mkdir -p "$d/.claude"
printf '{\n  "permissions": {"allow": ["Bash(ls)"]},\n  "enabledPlugins": {"other@else": true},\n  "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/mine.sh"}]}]}\n}\n' > "$d/.claude/settings.json"
run_init "$d"
python3 - "$d/.claude/settings.json" <<'PY' && ok "다른 키(permissions·hooks)와 다른 플러그인 등록을 보존한 채 두 키만 더한다" || ng "settings.json 병합이 기존 내용을 잃거나 등록을 빠뜨렸다"
import json, sys
o = json.load(open(sys.argv[1]))
assert o['permissions'] == {'allow': ['Bash(ls)']}
assert o['enabledPlugins'] == {'other@else': True, 'mdm@my-dev-method': True}
assert o['hooks']['Stop'][0]['hooks'][0]['command'].endswith('/mine.sh')
assert 'my-dev-method' in o['extraKnownMarketplaces']
PY
d=$(fresh fx2b); mkdir -p "$d/.claude"; printf '{ not json' > "$d/.claude/settings.json"
run_init "$d"
if [ "$RC" != 0 ] && [ "$(cat "$d/.claude/settings.json")" = '{ not json' ]; then ok "깨진 settings.json 은 건드리지 않고 **실패**한다 (조용히 덮지 않는다)"
else ng "깨진 settings.json 에서 rc=$RC — 덮어썼거나 성공으로 위장했다"; fi
d=$(fresh fx2c); mkdir -p "$d/.claude"; printf '{"enabledPlugins": {"mdm@my-dev-method": false}}\n' > "$d/.claude/settings.json"
run_init "$d"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["enabledPlugins"]["mdm@my-dev-method"] is False' "$d/.claude/settings.json" \
  && grep -q '꺼져 있다' "$TMP/out" && ok "프로젝트가 꺼 둔 등록(false)은 켜지 않고 알린다" || ng "프로젝트가 끈 플러그인을 설치기가 켰거나 알리지 않았다"

echo
echo "3. 1.x 잔재 분류 — 내용 해시로만 (합성 매니페스트)"
# 합성 1.x 제품: 현재 양식으로 설치한 뒤 옛 .claude/ 파일을 심고, 그중 일부의 해시만 매니페스트에 올린다.
manifest_of() { printf '%s' "$TMP/$1.manifest.tsv"; }   # make_legacy 가 쓰는 합성 매니페스트 경로 (명령치환 서브셸이라 전역으로 못 넘긴다)
make_legacy() { # $1 이름 → 경로. 합성 매니페스트는 manifest_of "$1"
  local d; d=$(fresh "$1")
  bash "$INIT" "$d" >/dev/null 2>&1 || { echo "합성 설치 실패" >&2; return 1; }
  mkdir -p "$d/.claude/commands" "$d/.claude/agents" "$d/.claude/hooks" "$d/.claude/scripts"
  printf 'KIT-SAME adopt\n'       > "$d/.claude/commands/mdm-adopt.md"        # 같음
  printf 'KIT-SAME review\n'      > "$d/.claude/commands/mdm-review.md"       # 같음
  printf 'PROJECT-EDITED plan\n'  > "$d/.claude/commands/mdm-plan.md"         # 다름 (키트 이름, 내용 다름)
  printf 'OWN deploy\n'           > "$d/.claude/commands/deploy.md"           # 키트가 쓴 적 없는 이름
  printf 'KIT-SAME agent\n'       > "$d/.claude/agents/mdm-code-review.md"    # 같음
  printf '#!/bin/sh\nKIT-SAME secrets\n'   > "$d/.claude/hooks/guard-secrets.sh"     # 같음
  printf '#!/bin/sh\nPROJECT-EDITED stat\n' > "$d/.claude/hooks/status-updated.sh"  # 다름
  printf 'KIT-SAME engine\n'      > "$d/.claude/scripts/check-consistency.sh" # 같음
  printf 'KIT-SAME readme\n'      > "$d/.claude/README.md"                    # 같음
  # settings.json: 1.x 훅 등록 3건 + 프로젝트 훅 1건 + permissions
  python3 - "$d/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; o = json.load(open(p))
o['permissions'] = {'allow': ['Bash(ls)']}
o['hooks'] = {
  'PreToolUse': [{'matcher': 'Bash', 'hooks': [
      {'type': 'command', 'command': '$CLAUDE_PROJECT_DIR/.claude/hooks/guard-dependency.sh'},
      {'type': 'command', 'command': '$CLAUDE_PROJECT_DIR/.claude/hooks/guard-secrets.sh'}]}],
  'Stop': [{'hooks': [
      {'type': 'command', 'command': '$CLAUDE_PROJECT_DIR/.claude/hooks/status-updated.sh'},
      {'type': 'command', 'command': '$CLAUDE_PROJECT_DIR/.claude/hooks/mine.sh'}]}]}
json.dump(o, open(p, 'w'), indent=2, ensure_ascii=False)
PY
  sed 's/dev-kit v[0-9.]*/dev-kit v1.0.0/' "$d/CLAUDE.md" > "$d/c.t" && mv "$d/c.t" "$d/CLAUDE.md"
  # 프로젝트 소유 데이터
  printf '\n| C01 | 첫 사이클 | 진행 |\n' >> "$d/docs/plan/index.md"
  printf '\n| ADR-001 | 스택 결정 | 채택 |\n' >> "$d/docs/decisions/index.md"
  mkdir -p "$d/docs/evidence/readiness" "$d/docs/meta"; printf 'project evidence' > "$d/docs/evidence/readiness/keep.json"; printf 'project config' > "$d/docs/meta/project.json"
  printf '# PROJECT source-map\n' > "$d/docs/spec/source-map.md"
  printf 'project owned workflow\n' > "$d/.github/workflows/mdm-check.yml"
  printf '# OLD GUIDE\n' > "$d/docs/guides/ready.md"
  MAN="$(manifest_of "$1")"
  {
    printf '# path\tversions\tsha256\n'
    for rel in .claude/commands/mdm-adopt.md .claude/commands/mdm-review.md .claude/agents/mdm-code-review.md .claude/hooks/guard-secrets.sh .claude/scripts/check-consistency.sh .claude/README.md; do
      printf '%s\t1.0.0\t%s\n' "$rel" "$(sha "$d/$rel")"
    done
    # 「다름」 파일은 경로만 올리고 해시는 다른 값으로
    printf '.claude/commands/mdm-plan.md\t1.0.0\t%s\n' "$(printf 'x' | (sha256sum 2>/dev/null || shasum -a 256) | cut -d' ' -f1)"
    printf '.claude/hooks/status-updated.sh\t1.0.0\t%s\n' "$(printf 'y' | (sha256sum 2>/dev/null || shasum -a 256) | cut -d' ' -f1)"
    printf '.claude/settings.json\t1.0.0\t%s\n' "$(printf 'z' | (sha256sum 2>/dev/null || shasum -a 256) | cut -d' ' -f1)"
  } > "$MAN"
  printf '%s' "$d"
}
LEGACY_ALL=".claude/commands/mdm-adopt.md .claude/commands/mdm-review.md .claude/commands/mdm-plan.md .claude/commands/deploy.md .claude/agents/mdm-code-review.md .claude/hooks/guard-secrets.sh .claude/hooks/status-updated.sh .claude/scripts/check-consistency.sh .claude/README.md"
n_all=$(printf '%s\n' $LEGACY_ALL | grep -c .)

d=$(make_legacy fx3) || exit 1; MAN="$(manifest_of fx3)"
before=$(cd "$d" && cksum $LEGACY_ALL 2>/dev/null | sort); n_before=$(printf '%s' "$before" | grep -c .)
[ "$n_before" = "$n_all" ] || ng "합성본에 잔재가 ${n_before}/${n_all} 개뿐이다 — 이 단언은 부분만 잰다 (통과로 위장하지 않는다)"
MDM_LEGACY_MANIFEST="$MAN" bash "$INIT" "$d" --upgrade > "$TMP/out" 2>&1; RC=$?
[ "$RC" = 0 ] || { ng "업그레이드 rc=$RC"; tail -5 "$TMP/out" | sed 's/^/      /'; }
after=$(cd "$d" && cksum $LEGACY_ALL 2>/dev/null | sort); n_after=$(printf '%s' "$after" | grep -c .)
if [ "$before" = "$after" ] && [ "$n_after" = "$n_all" ]; then ok "**기본 업그레이드는 잔재 ${n_all}개를 그대로 둔다** — 같음·다름·남의 것 전부"
else ng "기본 업그레이드가 잔재를 건드렸다:
$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's/^/      /')"; fi
ls "$d/.claude/commands" "$d/.claude/hooks" | grep -q 'retired' && ng "플래그 없이 개칭했다" || ok "플래그 없이는 개칭 흔적도 없다"
grep -q 'mdm-adopt.md  (dev-kit 1.0.0)' "$TMP/out" && grep -q 'guard-secrets.sh  (dev-kit 1.0.0)' "$TMP/out" \
  && ok "「원본과 같은 파일」을 판별 버전과 함께 알린다" || ng "「같음」 분류가 출력에 없다"
grep -q 'mdm-plan.md' "$TMP/out" && grep -q 'status-updated.sh' "$TMP/out" && grep -q '내용이 다른 파일' "$TMP/out" \
  && ok "「이름은 같고 내용이 다른 파일」을 따로 알린다 (건드리지 않는다)" || ng "「다름」 분류가 출력에 없다"
grep -q 'deploy.md' "$TMP/out" && ng "키트가 쓴 적 없는 이름(deploy.md)까지 잔재로 보고했다" || ok "키트가 쓴 적 없는 이름은 보고하지 않는다 (이 저장소 것이다)"
grep -q '훅 등록 3건' "$TMP/out" && ok "settings.json 의 1.x 훅 등록 수(3)를 센다" || ng "1.x 훅 등록 수를 세지 않거나 틀렸다"
grep -q '아무것도 건드리지 않았다' "$TMP/out" && grep -q -- '--retire-legacy' "$TMP/out" \
  && ok "불간섭을 말하고 옵트인 플래그를 안내한다" || ng "불간섭 선언이나 플래그 안내가 없다"
# 4. 업그레이드의 소유권
grep -q 'C01' "$d/docs/plan/index.md" && grep -q 'ADR-001' "$d/docs/decisions/index.md" && ok "카탈로그 행(사이클 현황·ADR 목록)을 보존한다" || ng "카탈로그 행을 지웠다"
[ "$(cat "$d/docs/evidence/readiness/keep.json")" = 'project evidence' ] && [ "$(cat "$d/docs/meta/project.json")" = 'project config' ] && ok "docs/meta·docs/evidence 를 보존한다" || ng "증거·설정을 건드렸다"
grep -q 'PROJECT source-map' "$d/docs/spec/source-map.md" && ok "프로젝트가 채운 source-map.md 를 보존한다" || ng "source-map.md 를 양식으로 덮었다"
[ "$(cat "$d/.github/workflows/mdm-check.yml")" = 'project owned workflow' ] && ok "기존 CI 워크플로를 보존한다" || ng "CI 워크플로를 덮었다"
cmp -s "$d/docs/guides/ready.md" "$PLUGIN/templates/docs/guides/ready.md" && ok "키트 소유 가이드는 새 판으로 갈아 준다" || ng "가이드를 갈지 않았다"
[ -f "$d/CLAUDE.md.dev-kit-new" ] && grep -q 'dev-kit v1.0.0' "$d/CLAUDE.md" && ok "CLAUDE.md 는 덮지 않고 .dev-kit-new 사이드카를 둔다" || ng "CLAUDE.md 처리가 약속과 다르다"
grep -q "MDM_KIT_REF 가 있으면 그 핀을 v${PLUGIN_VER}" "$TMP/out" && ok "CI 핀은 있을 때만 올리라고 안내한다 (#427)" || ng "CI 핀 안내가 없거나 조건 없이 「올린다」고 한다"

echo
echo "3-1. 1.x CI 워크플로 — 핀이 없으면 양식을 사이드카로 두고 교체를 안내한다 (#427)"
d=$(fresh fx3c); run_init "$d"
printf 'name: MDM project checks\non: [push]\njobs:\n  mdm-check:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - run: bash .claude/scripts/mdm-check.sh\n' > "$d/.github/workflows/mdm-check.yml"
before_ci=$(cat "$d/.github/workflows/mdm-check.yml")
run_init "$d" --upgrade
[ "$RC" = 0 ] || ng "1.x CI 업그레이드 rc=$RC"
[ "$(cat "$d/.github/workflows/mdm-check.yml")" = "$before_ci" ] && ok "1.x CI 파일은 덮지 않는다 (프로젝트 소유)" || ng "1.x CI 파일을 덮었다"
cmp -s "$d/.github/workflows/mdm-check.yml.dev-kit-new" "$PLUGIN/templates/.github/workflows/mdm-check.yml" \
  && ok "핀 없는 CI 옆에 2.0.0 양식을 mdm-check.yml.dev-kit-new 로 둔다" || ng "핀 없는 CI 에 양식 사이드카를 남기지 않았다"
grep -q 'MDM_KIT_REF 가 없다' "$TMP/out" && grep -q 'mdm-check.yml.dev-kit-new' "$TMP/out" \
  && ok "「핀이 없다 → 사이드카로 교체」를 안내한다 (올릴 핀이 없는데 「올린다」고 하지 않는다)" || ng "핀 없는 CI 의 다음 행동을 안내하지 않는다"
grep -q '옛 엔진 경로 .claude/scripts/' "$TMP/out" \
  && ok "옛 엔진 경로를 부르는 CI 는 --retire-legacy 뒤 깨진다고 알린다" || ng "옛 엔진 경로를 부르는 CI 를 알리지 않는다"

echo
echo "4. --retire-legacy — 해시가 같은 것만 개칭, 등록도 그 훅 것만"
d=$(make_legacy fx4) || exit 1; MAN="$(manifest_of fx4)"
MDM_LEGACY_MANIFEST="$MAN" bash "$INIT" "$d" --upgrade --retire-legacy > "$TMP/out" 2>&1; RC=$?
[ "$RC" = 0 ] || { ng "retire rc=$RC"; tail -5 "$TMP/out" | sed 's/^/      /'; }
n_ret=$(cd "$d" && ls .claude/commands/*.dev-kit-1x-retired .claude/agents/*.dev-kit-1x-retired .claude/hooks/*.dev-kit-1x-retired .claude/scripts/*.dev-kit-1x-retired .claude/README.md.dev-kit-1x-retired 2>/dev/null | wc -l | tr -d ' ')
[ "$n_ret" = 6 ] && ok "「같음」 6개만 *.dev-kit-1x-retired 로 개칭한다 (지우지 않는다)" || ng "개칭된 수가 6이 아니라 ${n_ret}이다"
[ -f "$d/.claude/commands/mdm-plan.md" ] && [ "$(cat "$d/.claude/commands/mdm-plan.md")" = 'PROJECT-EDITED plan' ] \
  && [ -f "$d/.claude/hooks/status-updated.sh" ] && ok "「다름」 파일(mdm-plan.md·status-updated.sh)은 --retire-legacy 로도 건드리지 않는다" \
  || ng "내용이 다른 파일을 개칭했다 — 사용자 파일을 잃을 수 있는 경로"
[ -f "$d/.claude/commands/deploy.md" ] && ok "남의 파일(deploy.md)은 그대로다" || ng "남의 파일을 건드렸다"
python3 - "$d/.claude/settings.json" <<'PY' && ok "settings.json: 물린 훅(guard-secrets)의 등록만 빼고 다른 훅(guard-dependency 파일 없음·status-updated 변경됨·mine.sh)·permissions·플러그인 등록은 남긴다" || ng "settings.json 훅 등록 정리가 약속과 다르다"
import json, sys
o = json.load(open(sys.argv[1]))
cmds = [h['command'] for gs in o['hooks'].values() for g in gs for h in g['hooks']]
assert not any(c.endswith('/guard-secrets.sh') for c in cmds), cmds
assert any(c.endswith('/guard-dependency.sh') for c in cmds), cmds     # 파일이 없는 등록은 판단 근거가 없다 — 남긴다
assert any(c.endswith('/status-updated.sh') for c in cmds), cmds       # 변경된 훅 파일의 등록은 남긴다
assert any(c.endswith('/mine.sh') for c in cmds), cmds
assert o['permissions'] == {'allow': ['Bash(ls)']}
assert o['enabledPlugins']['mdm@my-dev-method'] is True
PY
grep -q '훅 등록 1건 제거' "$TMP/out" && ok "제거한 등록 수(1)를 보고한다" || ng "등록 제거 보고가 없거나 수가 틀렸다"
d=$(fresh fx4b); run_init "$d" --retire-legacy
[ "$RC" != 0 ] && ok "--retire-legacy 는 --upgrade 없이 쓸 수 없다" || ng "--retire-legacy 단독 실행을 막지 않았다"

echo
echo "4-1. 실패 경로 — 복사·쓰기가 실패하면 「완료」를 찍지 않고 멈춘다 (#429 #443 #447 #451)"
[ "$(id -u)" = 0 ] && ng "root 로는 쓰기 실패를 만들 수 없다 — 이 절은 일반 사용자로 돌린다"
d=$(fresh fx7); run_init "$d"
first_guide=$(cd "$PLUGIN/templates" && find docs/guides -type f -name '*.md' | sort | head -1)
printf 'OLD\n' > "$d/$first_guide"; printf 'OLD\n' > "$d/docs/guides/S6-build.md"
chmod 444 "$d/$first_guide"
run_init "$d" --upgrade
chmod 644 "$d/$first_guide"
if [ "$RC" != 0 ] && grep -q '복사 실패' "$TMP/out" && ! grep -q '업그레이드 완료' "$TMP/out"; then
  ok "가이드 하나를 못 쓰면 rc≠0 으로 멈추고 「업그레이드 완료」를 찍지 않는다 (#429 — 파이프라인 서브셸이 die 를 삼키던 자리)"
else
  ng "가이드 쓰기 실패 뒤에도 계속 갔다 (rc=$RC, 완료 줄 $(grep -c '업그레이드 완료' "$TMP/out"))"
fi
d=$(make_legacy fx8) || exit 1
MDM_LEGACY_MANIFEST="$TMP/no-such-manifest.tsv" bash "$INIT" "$d" --upgrade > "$TMP/out" 2>&1; RC=$?
[ "$RC" != 0 ] && grep -q '매니페스트' "$TMP/out" && ok "1.x 판별 매니페스트가 없으면 조용히 0건으로 보고하지 않고 멈춘다 (#443)" || ng "매니페스트 없이 rc=$RC 로 진행했다 — 잔재 보고가 조용히 꺼진다"
for bad in '{"enabledPlugins": ["a@b"]}' '{"extraKnownMarketplaces": "x"}' '{"enabledPlugins": null}'; do
  d=$(fresh fx9); mkdir -p "$d/.claude"; printf '%s\n' "$bad" > "$d/.claude/settings.json"
  run_init "$d"
  if [ "$RC" != 0 ] && [ "$(cat "$d/.claude/settings.json")" = "$bad" ]; then ok "settings.json 의 객체 아닌 값($bad)은 덮지 않고 멈춘다 (#451)"
  else ng "객체 아닌 값($bad)을 덮었거나 계속 갔다 (rc=$RC): $(cat "$d/.claude/settings.json" | tr -d '\n' | head -c 80)"; fi
done
d=$(fresh fx10); mkdir -p "$d/.claude"; printf '{"permissions": {}}\n' > "$TMP/shared-settings.json"; ln -s "$TMP/shared-settings.json" "$d/.claude/settings.json"
run_init "$d"
if [ -L "$d/.claude/settings.json" ] && grep -q 'mdm@my-dev-method' "$TMP/shared-settings.json"; then ok "settings.json 이 심볼릭 링크면 링크를 지키고 대상 파일에 쓴다 (#451)"
else ng "settings.json 링크를 일반 파일로 바꿨거나 대상에 쓰지 않았다"; fi
d=$(fresh fx11); printf 'node_modules/\n' > "$d/.gitignore"; chmod 444 "$d/.gitignore"
run_init "$d"; chmod 644 "$d/.gitignore"
[ "$RC" != 0 ] && ! grep -q 'gitignore 추가' "$TMP/out" && ok ".gitignore 를 못 쓰면 「추가」를 찍지 않고 멈춘다 (#447)" || ng ".gitignore 쓰기 실패 뒤 rc=$RC 로 「추가」를 찍었다"

echo
echo "5. 배포본 무결성 · 실물 매니페스트 · 래퍼"
cp -R "$PLUGIN" "$TMP/plugin-broken"
sed 's/"version": "[0-9.]*"/"version": "9.9.9"/' "$PLUGIN/.claude-plugin/plugin.json" > "$TMP/plugin-broken/.claude-plugin/plugin.json"
d=$(fresh fx5); bash "$TMP/plugin-broken/scripts/init-project.sh" "$d" > "$TMP/out" 2>&1; RC=$?
[ "$RC" != 0 ] && grep -q '배포본이 깨졌다' "$TMP/out" && [ ! -e "$d/CLAUDE.md" ] \
  && ok "스탬프 ≠ plugin.json version 이면 아무것도 심지 않고 죽는다" || ng "버전 불일치 배포본이 설치됐다 (rc=$RC)"
real="$PLUGIN/scripts/legacy-manifest.tsv"
if [ -f "$real" ] && awk -F'\t' '!/^#/ && NF==3' "$real" | grep -q . ; then
  bad_rows=$(awk -F'\t' '!/^#/ && (NF!=3 || $3 !~ /^[0-9a-f]{64}$/)' "$real" | wc -l | tr -d ' ')
  [ "$bad_rows" = 0 ] && ok "실물 legacy-manifest.tsv 의 모든 행이 path·versions·sha256 3열이다" || ng "실물 매니페스트에 형식이 어긋난 행 ${bad_rows}개"
  for rel in .claude/commands/mdm-adopt.md .claude/hooks/guard-secrets.sh .claude/scripts/check-consistency.sh .claude/settings.json .claude/README.md; do
    awk -F'\t' -v k="$rel" '$1==k && $2 ~ /(^|,)1\.0\.0(,|$)/' "$real" | grep -q . || ng "실물 매니페스트에 1.0.0 의 $rel 이 없다"
  done
  ok "실물 매니페스트가 1.0.0 의 커맨드·훅·스크립트·settings·README 를 포함한다 (빠진 것은 위에 실패로 찍힌다)"
else
  ng "실물 legacy-manifest.tsv 가 없거나 비었다"
fi
d=$(fresh fx5b); bash "$ROOT/scripts/install-kit.sh" "$d" > "$TMP/out" 2>&1; RC=$?
[ "$RC" = 0 ] && [ -f "$d/CLAUDE.md" ] && ok "옛 진입점 scripts/install-kit.sh 가 플러그인 설치기로 위임한다" || ng "옛 진입점 래퍼가 동작하지 않는다 (rc=$RC)"

echo
echo "뮤테이션 자기검증"
# 해시 대조를 끄면(모두 「같음」으로 분류) 「다름」 파일이 개칭돼야 한다 — 그래야 위 4절이 진짜로 그 분기를 잰 것이다.
mkdir -p "$TMP/mut/scripts" "$TMP/mut/.claude-plugin"; cp -R "$PLUGIN/templates" "$TMP/mut/templates"; cp "$PLUGIN/.claude-plugin/plugin.json" "$TMP/mut/.claude-plugin/"
sed 's|^    if \[ -n "\$ver" \]; then LEGACY_SAME|    if true; then LEGACY_SAME|' "$INIT" > "$TMP/mut/scripts/init-project.sh"
if ! grep -q 'if true; then LEGACY_SAME' "$TMP/mut/scripts/init-project.sh"; then
  ng '뮤테이션 지점(classify_legacy 의 해시 판정 줄)을 찾지 못했다 — 이 fixture 를 갱신한다'
else
  d=$(make_legacy fx6) || exit 1; MAN="$(manifest_of fx6)"
  MDM_LEGACY_MANIFEST="$MAN" bash "$TMP/mut/scripts/init-project.sh" "$d" --upgrade --retire-legacy > "$TMP/out" 2>&1; mrc=$?
  if [ "$mrc" != 0 ] || ! grep -q '업그레이드 완료' "$TMP/out"; then
    ng "뮤턴트가 정상 종료하지 않았다 (rc=$mrc) — 이 자기검증은 아무것도 재지 못한다"; tail -3 "$TMP/out" | sed 's/^/      /'
  elif [ -f "$d/.claude/commands/mdm-plan.md" ]; then
    ng "해시 대조를 껐는데도 「다름」 파일이 남았다 — fixture 가 해시 분기를 재고 있지 않다"
  else
    ok "해시 대조를 끄면 「다름」 파일이 개칭된다 (fixture 가 진짜로 해시 분기를 재고 있다)"
  fi
fi

echo
if [ "$fail" = 0 ]; then echo "init-project.sh 설치·업그레이드 회귀 통과"; else echo "init-project.sh 설치·업그레이드 회귀 실패"; exit 1; fi
