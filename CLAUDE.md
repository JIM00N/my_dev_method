# my_dev_method — dev-kit 개발 저장소

기계적으로 강제되는 개발방법론 키트를 **Claude Code 플러그인**(`plugins/mdm/`, 마켓플레이스 `.claude-plugin/marketplace.json`)으로 만드는 저장소다.
플러그인은 커맨드(`/mdm:…`)·서브에이전트(`mdm:…`)·훅(`hooks/hooks.json`)·검사 엔진(`scripts/`, 런처 `bin/mdm`)을 제공하고,
`plugins/mdm/templates/`(CLAUDE.md·AGENTS.md·docs/·제품 CI 양식)만 `/mdm:init` 이 제품에 심는다 (2.0.0 — 1.x 는 `.claude/` 를 통째로 복사했다).
`plugins/mdm/templates/CLAUDE.md`는 **배포 양식**이다 — 제품 저장소용 규칙이지, 이 저장소의 작업 규칙이 아니다.
**엔진은 플러그인 캐시에서 돈다** — 제품 루트는 `MDM_PROJECT_ROOT` → `CLAUDE_PROJECT_DIR` → git 루트 → 현재 디렉토리 순으로 정한다 (`plugins/mdm/scripts/mdm_env.py` 머리말이 정본).
훅은 같은 출발점에서 표식 `docs/status/STATUS.md` 를 git 최상위까지 위로 찾는다 (`plugins/mdm/hooks/lib-root.sh`).
로컬에서 써 보려면 `claude --plugin-dir plugins/mdm` (파일을 고치면 `/reload-plugins`).

## 세션 시작

1. `STATUS.md`를 읽는다 — 버전, 지금 하는 일, 열린 이슈.
2. 이슈 상세는 `issues.md`(로컬 전용), 공개 기록은 `CHANGELOG.md`.

## 절대 규칙

1. **변경 후 커밋 전에 `/mdm-kit-review`를 돌린다.** 코드리뷰는 서브에이전트가 한다 —
   Main이 직접 diff를 평가해 "통과"를 선언하지 않는다. 만든 컨텍스트는 자기 구멍을 보지 못한다.
   축마다 서로 다른 에이전트를 쓴다 (`.claude/commands/mdm-kit-review.md`가 정본).
   장치: **git 네이티브 pre-commit 훅**(`.githooks/pre-commit`)이 커밋될 트리가 통과 도장
   (`review-stamp.sh`, git write-tree)과 일치할 때만 커밋을 허용한다. git이 커밋 시점에 직접 돌리므로
   **명령 표기를 바꾸는 것으로는** 못 피하고(`sh -c`·서브셸·`$(...)`·백틱·함수·줄이음 6가지를
   `test-review-gate.sh`가 **실제 커밋으로** 검증한다), `<pathspec>`·`-a`·`--amend` 등 부분·대체 인덱스 모드도 막힌다.
   도장 스크립트가 없거나 실행 권한이 없어도 **차단**한다(fail-closed).
   병합 커밋은 `pre-merge-commit` 훅이 따로 막는다(git 2.24+). 활성화(클론마다 한 번): `git config core.hooksPath .githooks`.
   **게이트는 에이전트 셸에서만 건다** (`CLAUDECODE`·`AI_AGENT` 표식). 사용자가 자기 터미널에서 하는 커밋은 막지 않는다 —
   사용자는 리뷰 지적의 반영 여부를 정하는 **권한자**이지 통제 대상이 아니고, 이 게이트가 겨냥하는 것은
   "세션이 길어지면 산문 규칙이 드리프트한다"(리뷰를 잊는 에이전트) 하나다.
   **정직한 한계 (전부 정책 위반으로 다룬다)** — 이 장치가 기계로 보장하는 것은 "커밋 트리 == 도장 트리"까지다:
   ① 도장이 "리뷰가 실제로 돌았음"을 증명하지는 못한다(도장은 `--write`로 찍힌다). ② `git commit --no-verify`·
   `git -c core.hooksPath=… commit`은 훅 자체를 끈다. ③ cherry-pick·revert·rebase 재생 커밋은
   git이 차단형 pre-* 훅을 주지 않아 못 막는다(issues #028 — 보조 훅 도입은 사용자 판단 대기).
   ④ **에이전트 셸 한정 분기 자체가 우회구다** — `env -u CLAUDECODE -u AI_AGENT git commit`(또는 빈 문자열 대입)이면
   게이트가 꺼진다. 표식을 늘리면 사용자를 잘못 막을 위험이 커지므로 늘리지 않는다(#035).
   **요약: 이 게이트는 "잊고 커밋하는 것"을 막지, "작정하고 우회하는 것"은 못 막는다.**
2. **리뷰는 1회전이다.** 한 번 돌리고, 발견을 고치고, **재리뷰 없이** 진행한다.
   세는 법·수정 후 처리·남은 치명 처리는 `.claude/commands/mdm-kit-review.md` 4번이 정본이다.
   (2026-08-28 확정 — 사용자 결정. 그전에는 상한 3회전이었다)
   **1회전은 사용자가 정한 작업 예산이다.** 후속 실측은 재리뷰가 과거 결함도 찾았음을 확인했다.
   “수정이 계속 새 결함만 만든다”는 일반화는 철회한다. 회전 상한은 유지하고 수정의 근거는
   재현 fixture와 기계 검사가 맡는다. 과거 관측은 STATUS의 보존 기록을 참고한다.
   치명·높음이 남거나 수정 자체가 새 위험을 만든다고 판단되면 약화시키지 않고 `STATUS.md` 에 ⛔ 로 올려
   **사용자 판단을 받는다.**
2-1. **커밋 정책: 승인 모드.** 리뷰를 통과시킨 뒤 **묻고 답을 받아야** 커밋한다. 물을 때 무엇이 바뀌었는지·
   리뷰 결과·남은 지적을 함께 준다. **모드와 무관하게 승인받는 것**은 여기서 세지 않는다 —
   `plugins/mdm/templates/docs/guides/commit-policy.md`의 「어느 쪽이든 반드시 묻는 것」 표가 정본이고,
   이 저장소도 그 표를 그대로 따른다 (세는 순간 갈라진다 — 실제로 갈라졌었다: issues #041·#053).
   **이 규칙에는 기계 장치가 없다** — 규칙 1의 게이트는 "트리 == 도장"만 보고 승인 여부는 모른다.
   (키트 쪽 정본은 `plugins/mdm/templates/docs/guides/commit-policy.md` — 제품 저장소는 S1에서 사용자가 고른다)
3. **약속을 적으면 강제 장치를 같이 만든다.** 키트 문서에 "막는다/검사한다/강제한다"를 쓰는 순간
   그 검사가 어디 있는지(스크립트·훅·fixture)를 함께 만들거나, 못 만들면 그 문장을 약속이 아닌
   권고로 고쳐 쓴다. **구현 없는 약속이 이 저장소의 제1 결함 유형이다** (2026-08 외부 리뷰로 확인).
4. **키트 동작이 바뀌면 워크플로 아티팩트 페이지도 갱신한다** (URL은 메모리 `workflow-artifact`).
5. **작업 종료 시 `STATUS.md`를 갱신한다.**

## 리뷰 축 (정본: `.claude/commands/mdm-kit-review.md`)

K1 약속–강제 대조 · K2 우회 재현(실행 기반) · K3 셸 정확성 · K4 수명주기 경로 ·
K5 의미적 문서 정합 · K6 회귀 증거 — 치명·높음은 `mdm-kit-refute`가 반증을 시도한 뒤에만 확정된다.
**반증 경유에는 기계 장치가 없다** — 절차이고, 관측되는 흔적은 `issues.md` 회전 표의 반증 결과 칸뿐이다
(`.claude/commands/mdm-kit-review.md` 3단계가 정본).

## 이 저장소에서 밟은 셸 함정 (다시 밟지 않는다)

> **0.8.0 — 마크다운을 셸로 파싱하는 일은 이제 하지 않는다.** 같은 결함 계열이 표 리더
> **다섯 개**에서 확정됐고(`table_of` #269 · `reg_table` · `data_rows` #267 · `plan_rows` #279 ·
> `plan_scan` #357·#358), 회전을 늘려 닫히는 종류가 아니라고 판단해 **검사 J 의 파서를
> `plugins/mdm/scripts/check-plan.py`(파이썬)로 옮겼다** (사용자 결정 — 갈래 A).
> 아래 세 함정은 **아직 셸인 A~I**(`table_of`·`data_rows`·`reg_table`)에 그대로 적용된다.
> 새 표 리더가 필요하면 셸에 하나 더 만들지 말고 파이썬 쪽에 붙인다.


- **`$변수` 뒤에 곧바로 멀티바이트 문자를 쓰지 않는다** — bash 가 그 바이트를 변수명에 붙여 읽어
  `set -u` 아래에서 죽는다. `「$sect」`가 아니라 `「${sect}」`. 검사기에서 이러면 **보고 경로만 죽어**
  검사가 아무것도 못 잡는 상태가 된다 (2026-08-27 실측).
- **awk 로 한글 문자열을 `==` 비교하지 않는다** — macOS 기본 awk(20200816)는 비-ASCII 문자열 둘을
  무조건 같다고 판정한다. `index()`는 정상이다. 표 처리는 순수 bash 로 한다
  (`plugins/mdm/scripts/check-consistency.sh` 33행에 같은 경고가 있다).
- **줄 단위 grep 으로 여러 줄에 걸친 호출을 뽑지 않는다** — 추출 0건이면 검사가 **통과로 위장**한다.
  추출 결과가 비면 그 자체를 실패 신호로 낸다.

## 자동 검증

- `scripts/check-docs.sh` + `scripts/check-docs.py` — 경로·참조(키트 + **이 저장소 자신**) ·
  **절 이름 포인터** · **축↔에이전트 대응** · 쓰기 도구 에이전트의 임시 디렉토리 제한 ·
  **셸 함정 lint** · **플러그인 이름 공간 정합(검사 11 — 파일명에 `mdm-` 접두 없음 · 에이전트 파일명 == name · `/mdm:…`·`mdm:…` 참조 실재 ·
  제품 양식에 `.claude/scripts/…`·옛 이름·맨 진입점 이름(`mdm-check.sh`·`check-consistency.sh`) 없음)** ·
  **플러그인 매니페스트 정합(검사 12 — plugin.json name == mdm · 버전이 CLAUDE.md 스탬프·marketplace 항목과 `metadata.version`·CI 핀·
  AGENTS.md·플러그인 README 의 `--branch v…` 와 일치 · marketplace source 실재 · hooks.json 훅 실재·실행 권한 · 런처)** · 훅/스크립트/런처 실행 권한 · 문법 ·
  (로컬) `issues.md` 번호 유일성
  (CI: `.github/workflows/docs-check.yml`)
- `scripts/test-docs-check.sh` — **위 검사 자신의** 회귀 fixture (CI). **단언 47줄** (재는 법: `bash scripts/test-docs-check.sh | grep -cE '^  (통과|실패)  '`.
  한때 적었던 호출 지점 grep 은 `expect_red() {`·`expect_green() {` 정의 두 줄까지 세어 2 가 많았다 — 2.0.0 리뷰 반증이 잡았다).
  덮는 것은 **검사 1-c·5·6·7·8·9·10·11·12** 다 — 검사 1·1-b·2·3·4 는 아직 RED 증거가 없다(이슈 #159).
  하필 검사 3(훅 실행 권한)은 스스로 «이 검사가 유일한 그물»이라 적은 자리다. **"각 분기"가 아니다.**
- `scripts/test-review-gate.sh` — 커밋 게이트(pre-commit 훅·도장)의 우회 차단·시그널 정리 실측 (CI)
- `scripts/test-consistency.sh` — 정합성 검사 회귀 fixture: H 마일스톤 배치 · 준비도 롤업 · I 문서 등재 대조 ·
  **J 계획 깊이**(사양 표·권한 표·`self:plan` 경계·도입 전/후 양쪽 · **본체 호출 경계**) (CI).
  **실행 단언 170건**(그중 J 112) **+ 뮤테이션 자기검증 9** = 단언 179줄 (전체 출력 194줄 — 머리말·빈 줄 15 포함).
  **세는 기준을 함께 적는다** — `expect_*` 호출 지점은 159 이고, 거기에 루프 전개 +5 와
  손으로 쓴 `ok`/`ng` 단언 15(R10 3 + J35 1 + J35-b 1 + J38 1 + 뮤테이션 9)를 더해 단언 줄이 179 가 된다.
  재는 법: 단언 총계 `grep -cE '^  (통과|실패)  '` · J `grep -cE '^  (통과|실패)  J[0-9]'` ·
  뮤테이션은 「뮤테이션 자기검증」 줄 이후 · 호출 지점 `grep -cE '^\s*expect_(signal|no_signal|fail) '`.
  개수 주장이 두 회전 연속 틀렸던 자리다(1회전 24 vs 21 · 2회전 46 vs 50).
  **J 는 `expect_fail` 로 기대 메시지·«실패» 등급·rc=1 을 함께 단언한다** — 메시지만 보면
  `bad`→`caution` 강등이 무음으로 지나간다(1회전 K6 실측).
  **뮤테이션 9 중 둘은 조기 종료 두 자리를 각각 `exit 0` 으로 되돌려 뮤턴트의 rc 를 먼저 단언한다** —
  한때 그 자리는 주석만 「되돌리면」이라 쓰고 **코드는 뮤테이션을 안 가했다**(2회전 별건 #334).
  **둘은 `check-plan.py` 본체에 직접 뮤테이션을 가한다** — 셸의 호출 블록만 재면
  「셸이 J 를 부른다」까지만 증명되고 정작 판정하는 파일이 무검증으로 남는다 (0.8.0 이식이 만든 자리)
- `scripts/test-report.sh` — `report.py` 회귀 fixture: Story 문서 ↔ 사이클 축약 슬롯 공존 모드 (CI)
- `scripts/test-install-upgrade.sh` — `plugins/mdm/scripts/init-project.sh`(`mdm init`) 회귀 fixture (CI). **단언 49줄 = 케이스 48 + 뮤테이션 자기검증 1**
  (재는 법: `bash scripts/test-install-upgrade.sh | grep -cE '^  (통과|실패)  '`).
  재는 것: 신규 설치가 **문서 골격과 플러그인 등록만** 심는가(`.claude/` 키트 파일을 복사하지 않는가) · `.claude/settings.json` 의
  다른 키·다른 플러그인 등록을 보존한 채 두 키만 더하는가, 깨진 JSON 은 건드리지 않고 실패하는가 · **1.x 잔재를 내용 해시로만 분류**하는가
  (같음/다름/키트가 쓴 적 없는 이름 — 합성 매니페스트 `MDM_LEGACY_MANIFEST` 로 잰다) · 기본은 **불간섭**(9개 체크섬 대조, 몇 개를 쟀는지까지 단언)이고
  `--retire-legacy` 도 「같음」만 개칭하며 그 훅의 `settings.json` 등록만 빼는가 · 카탈로그 행·meta·evidence·source-map·기존 CI 워크플로 보존 ·
  키트 소유 가이드 교체 · CLAUDE.md 사이드카 · 스탬프≠plugin.json 이면 아무것도 심지 않고 죽는가 · 실물 `legacy-manifest.tsv` 형식과 1.0.0 포함 · 옛 진입점 래퍼 ·
  **핀 없는 1.x CI 옆에 양식 사이드카**(#427) · **실패 경로**(가이드 쓰기 실패 · 매니페스트 부재 · 객체 아닌 settings 값 · settings 링크 · `.gitignore` 쓰기 실패 — 「완료」를 찍지 않고 멈추는가).
  뮤테이션은 해시 대조를 끄면 「다름」 파일이 개칭되는 것을 보인다.
  옛 이름 처리를 설치기가 추측으로 하던 두 판은 리뷰가 **치명**으로 잡아 사용자 결정으로 걷어냈다(0.7.0) — 2.0.0 의 분류는 추측이 아니라 해시지만
  그 결정을 뒤집는 것은 사용자 몫이라 **옵트인 플래그**로만 둔다 (2026-09-11 사용자 승인 — issues #437).
- `scripts/test-hooks.sh` — 플러그인 훅 3개의 회귀 fixture (CI). **단언 15줄 = 케이스 12 + 뮤테이션 3.** 훅이 키트 표식(`docs/status/STATUS.md`)이 있는 저장소에서는
  막고(rc=2) 없는 저장소에서는 판정하지 않는가(rc=0) — 플러그인 훅은 켜진 모든 저장소에서 돌기 때문에 생긴 분기다 · 하위 디렉토리 세션은 git 최상위까지 올라가 막는가 ·
  `MDM_PROJECT_ROOT` 가 먼저인가 · git 밖에서는 상위 표식을 줍지 않는가 · 마커가 이미 있을 때 지우고 다시 막는가(GNU `stat` 흉내 셈으로 macOS 에서도 재는 #430). jq 가 없으면 건너뛰지 않고 실패한다.
- `scripts/test-launcher.sh` — `bin/mdm` 런처 회귀 fixture (CI). **단언 16줄 = 케이스 15 + 뮤테이션 1.** 분기표를 스텁 엔진으로 격리해 명령마다 대상 스크립트·인자를 단언하고
  (`final` = 정합성 → 인계), 실제 엔진으로 version·root·rc 64·`check --init` 을, 제품 CI 양식의 실행 줄을 yml 에서 뽑아 그대로, 심볼릭 링크 경유 호출을 잰다.
  런처를 실행하는 fixture 가 없어 `SCRIPTS` 오타에도 CI 가 전부 GREEN 이던 자리다(2.0.0 리뷰 #425).
- `plugins/mdm/scripts/check-plan.py` — **정합성 검사 J 의 본체** (0.8.0 이식).
  `check-consistency.sh` 가 부르고, **python3 가 없거나 이 파일이 없으면 건너뛰지 않고 실패**한다.
  이 결정으로 **python3 가 키트 강제 장치의 필수 의존**이 됐다 — 그전에는 `report.py` 의 열람용
  선택 의존이었고 그 파일이 *"python3 가 없어도 강제 장치는 그대로 돈다"* 고 약속했다. **철회했다**
  (키트 README 「필요한 것」이 정본)
- `.githooks/pre-commit`·`pre-merge-commit` — **에이전트 셸에서** 도장과 다른 트리의 커밋·병합 차단
  (절대 규칙 1의 장치, `core.hooksPath`로 활성. 사용자 커밋은 막지 않는다)
- **버전은 `plugins/mdm/.claude-plugin/plugin.json` 이 정본이고 여섯 자리에 따라 적힌다** — `plugins/mdm/templates/CLAUDE.md` 첫 줄 스탬프 ·
  `.claude-plugin/marketplace.json` 의 mdm 항목과 `metadata.version` · 제품 CI 양식 `plugins/mdm/templates/.github/workflows/mdm-check.yml` 의 `MDM_KIT_REF` ·
  제품 `AGENTS.md`·플러그인 README 의 `--branch v…`. 검사 12 가 일치를 강제한다. 릴리스 태그는 `v<버전>` (CI 핀이 그 태그를 받는다 — **커밋 뒤 태그를 만든다**).

> **검사를 새로 넣으면 그 검사가 붉어지는 fixture를 같이 넣는다.** 예외 없다.
> 한때 여기에 *"`check-docs.sh`는 검사기 자신이라 자기검증이 없다 — 손으로 뮤테이션을 돌려 확인한다"*고
> 적혀 있었다. **그 정책은 바로 다음 변경에서 실패했다** — 새로 넣은 검사 셋이 아무것도 못 잡는 상태로
> 커밋 직전까지 왔고, 손으로 돌린 확인은 저장소에 안 남아 아무것도 막지 못했다.
> 절대 규칙 3의 후단("못 만들면 권고로 고쳐 쓴다")은 **정말 못 만들 때만** 쓴다 —
> 만들 수 있는데 안 만들고 한계를 적는 것은 규칙을 지킨 게 아니라 **우회한 것**이다.

계약 근거·실행 증거·변경 운영 회귀: `python3 -m unittest discover -s scripts/tests -v` (CI와 동일).
합성 운영 리허설: `python3 scripts/run-pilot-rehearsal.py` (실제 제품 효과 측정과 구분).
