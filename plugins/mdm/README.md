# dev-kit — AI 개발 지시서 플러그인 (`mdm`)

**버전: 2.0.0** — Claude Code 플러그인 `mdm@my-dev-method`. 제품 저장소의 배포본 버전은 `CLAUDE.md` 첫 줄의
`<!-- dev-kit v… -->` 스탬프로, 플러그인 버전은 `mdm version` 으로 확인한다 (플러그인이 심는 양식의 스탬프와 plugin.json 버전이 다르면 `mdm init` 이 아무것도 심지 않고 멈춘다. 제품 쪽 스탬프는 `mdm init --upgrade` 가 인쇄만 한다 — 제품이 옛 판인지는 첫 줄 스탬프로 사람이 본다).

AI(Claude Code / Codex 등)와 함께 소프트웨어를 개발할 때 쓰는 **범용 지시서 + 문서 골격 + 강제 장치** 세트.
`my_dev_method` 저장소가 원본이다. **2.0.0 부터 강제 장치(커맨드·서브에이전트·훅·검사 엔진)는 플러그인이 제공**하고
제품 저장소에는 **지시서와 문서 골격만** 심는다(`/mdm:init`). 1.x 까지는 `.claude/` 를 통째로 복사했다 — 그 차이가
이 문서의 「1.x 에서 올라오기」 절이다.

**계획을 뽑아내는 일은 상류가 한다.** 이 키트가 맡는 것은 그다음 — 이미 있는 계획 문서를 받아
**구현 중에 문서가 서로 어긋나서 생기는 오류와 일탈을 막는 것**이다.
**어떤 계획 도구도 전제하지 않는다** — `/mdm:adopt`가 저장소 안을 먼저 뒤지고, 없으면 밖에 있는지 묻고,
그래도 없으면 `/mdm:plan`이 직접 만든다. 진입점은 `/mdm:adopt` 하나다.

## 필요한 것 ★

| 무엇 | 왜 | 없으면 |
|---|---|---|
| **Claude Code** (플러그인 지원판) | 커맨드 `/mdm:…` · 서브에이전트 `mdm:…` · 훅 · `mdm` 런처의 PATH 등록 | 검사 엔진은 밖에서도 돈다(아래 「Claude Code 밖에서」). 훅·커맨드는 안 돈다 |
| `bash` | 훅·정합성 검사 A~I·런처 | 강제 장치가 안 돈다 |
| **`python3` (3.7+)** | **정합성 검사 J**(`check-plan.py`) · 계약 근거 엔진 · 리포트 · `settings.json` 등록 | **검사 J 가 실패한다 — 건너뛰지 않는다** |
| **`mktemp`** | 검사 J 의 상태를 셸이 받아 오는 통로 | 정합성 검사가 실패한다 |
| `git` | 훅·형상 관리·제품 루트 판정 | 커밋 계열 장치가 안 돈다 |
| `jq` | guard 훅 2개의 입력 파싱 | guard 훅이 **경고만 남기고 통과**한다 |

> **python3 는 0.8.0 부터 선택이 아니라 필수다.** 검사 J 의 입력이 사람이 자유롭게 쓰는 마크다운이라
> 셸 파싱으로는 같은 결함 계열이 반복해 재발했고(표 리더 다섯 개에서 확정), 그 파서를 파이썬으로 옮기면서
> *"python3 가 없어도 강제 장치는 그대로 돈다"* 는 약속을 **철회했다.** `mdm check` 는 python3 가 없으면 J 를
> **건너뛰지 않고 실패**시킨다 — 조용히 안 도는 검사는 없는 검사다.
> **왜 3.7+ 인가** — 문법 때문이 아니다. `LC_ALL` 이 없거나 `C` 인 컨테이너·cron 환경에서 한글 출력이
> 살아남는 근거가 **PEP 538·540 이고 둘 다 3.7 도입**이다.

## 설치

```text
/plugin marketplace add JIM00N/my_dev_method      # 마켓플레이스 my-dev-method 등록 (한 번)
/plugin install mdm@my-dev-method                  # 플러그인 설치 (사용자 범위)
```

그다음 **제품 저장소에서** (Claude Code 를 그 저장소에서 연 채로):

```text
/mdm:init
```

`/mdm:init` 은 `mdm init "$PWD"` 를 돌려 다음을 심는다 — `CLAUDE.md` · `AGENTS.md` · `docs/` 전체 ·
`.github/workflows/mdm-check.yml`(없을 때만) · `.gitignore` 의 `docs/reports/` · **`.claude/settings.json` 의 플러그인 등록**
(`extraKnownMarketplaces.my-dev-method` + `enabledPlugins."mdm@my-dev-method"`, 프로젝트 범위 — 팀원이 저장소를 열면 같은 판을 받는다).
`CLAUDE.md` 나 `docs/` 가 이미 있으면 중단한다(`--upgrade` 를 쓰라고 안내). **`.claude/` 에 키트 파일을 복사하지 않는다.**

복사 후 할 일은 설치 출력의 「이어서 할 일」이 정본이다 — 요약하면: `CLAUDE.md` 머리 두 줄을 프로젝트 것으로 →
`docs/status/STATUS.md` 시작 기록 → 세션 재시작(등록 반영) → `/hooks` 로 훅 3개 확인 → **`/mdm:adopt`** (S0).

**로컬 개발판을 쓰려면** (원본 저장소를 고치면서 제품에 바로 써 볼 때):

```bash
claude --plugin-dir /경로/my_dev_method/plugins/mdm        # 그 세션에서만 이 판을 쓴다. 파일을 고치면 /reload-plugins
# 또는  /plugin marketplace add /경로/my_dev_method  → /plugin install mdm@my-dev-method
```

## 무엇이 어디에 있나

`CLAUDE.md`의 규칙은 산문이고, 세션이 길어지면 에이전트는 드리프트한다. 플러그인은 **드리프트해도 막히는 것**만 담는다.
규칙과 훅이 어긋나면 규칙이 아니라 훅이 실제 동작이다.

| 플러그인 경로 | 무엇 | 대응하는 규칙 |
|---|---|---|
| `.claude-plugin/plugin.json` | 이름 `mdm` · 버전 (제품 `CLAUDE.md` 스탬프와 같아야 한다) | — |
| `hooks/hooks.json` | 훅 등록 (Bash + Write/Edit 양쪽 경로 · Stop) — 1.x 의 `.claude/settings.json` hooks 항목이 여기로 왔다 | — |
| `hooks/status-updated.sh` | 도입 후에는 현재 변경의 인계 기록을 검사한다. 도입 전에는 STATUS 날짜를 확인하며 반복 차단 방지는 유지 | 절대 규칙 9 |
| `hooks/guard-dependency.sh` | `stack.md` 결정 표의 "선택" 열에 없는 패키지의 설치·매니페스트 편집을 **막는다** | 절대 규칙 4 |
| `hooks/guard-secrets.sh` | 비밀 파일·비밀값 형태 문자열의 `git commit`(`-a`·같은 명령의 `git add` 대상 포함)과 형상 관리 대상 파일 쓰기를 **막는다** | 절대 규칙 12 · S4 4부 |
| `bin/mdm` | 엔진 런처. Claude Code 가 PATH 에 올린다 — `mdm check` · `mdm final` · `mdm contract …` · `mdm ops …` · `mdm report …` · `mdm init …` · `mdm doctor` · `mdm root` · `mdm version` | — |
| `scripts/check-consistency.sh` (`mdm check`) | 문서 정합성 기계 검사 **10종(A~J)** — 상류 스냅샷 무결성·요구사항 커버리지·테스트 실재·상류 변경 재검토 잔존·고아 ID 인용·화면 정합·참조 깨짐·**마일스톤 배치**·**문서 등재 대조**·**계획 깊이**(J, `self:plan` 한정) | `docs/spec/source-map.md` · `docs/upstream/plan.md` |
| `scripts/check-plan.py` | **검사 J 의 본체** — 계획 문서의 3계층(요구사항→기능→사양)·사양 표 칸·권한 표. **python3 가 없으면 `mdm check` 가 실패한다**(건너뛰지 않는다) | `docs/upstream/plan.md` · `docs/guides/plan.md` P3 |
| `scripts/mdm-contract.py` (`mdm contract`) · `mdm_model.py` · `mdm_operations.py` · `mdm-ops.py` (`mdm ops`) | 계약 근거·실행 증거·운영 엔진 — adopt · register · inspect · ready · verify · render · catalog · handoff · sync · doctor | `docs/guides/contract-evidence.md` · `docs/guides/operating-loop.md` |
| `scripts/mdm-check.sh` (`mdm final`) | 최종 통합 검사 = 정합성 + 현재 인계. 종료·제품 CI | 절대 규칙 9 |
| `scripts/report.py` (`mdm report`) | (검사 아님) md 를 HTML 한 장으로 | — |
| `scripts/init-project.sh` (`mdm init`) | 제품 저장소 설치·업그레이드 (아래 소유권 표대로) | — |
| `scripts/legacy-manifest.tsv` | 1.x 가 제품에 복사하던 `.claude/` 키트 파일들의 판별 내용 해시 — 「1.x 에서 올라오기」의 근거 | — |
| `scripts/mdm_env.py` | 엔진 위치와 **제품 루트 판정** (아래) | — |
| `commands/*.md` | `/mdm:init` `/mdm:adopt` `/mdm:plan` `/mdm:ready` `/mdm:stage` `/mdm:review` `/mdm:cycle-close` `/mdm:ingest-errors` — 파일명에 `mdm-` 접두가 없다. 이름 공간 `mdm:` 은 플러그인이 붙인다 | — |
| `agents/code-review.md` · `agents/error-learning.md` | 서브에이전트 `mdm:code-review` · `mdm:error-learning` | 절대 규칙 11 · 5 |
| `templates/` | **제품에 심는 것** — `CLAUDE.md` · `AGENTS.md` · `docs/` · `.github/workflows/mdm-check.yml` | — |

**제품 루트 판정.** 엔진은 플러그인 캐시에 있어 자기 경로로는 제품을 못 찾는다. 순서는
`MDM_PROJECT_ROOT` → `CLAUDE_PROJECT_DIR`(훅) → `git rev-parse --show-toplevel` → 현재 디렉토리이고, `mdm root` 가 판정 결과를 보인다.
셸 스크립트가 정한 루트를 `MDM_PROJECT_ROOT` 로 내보내 파이썬 본체와 같은 제품을 보게 한다.
모노레포처럼 제품 루트가 git 루트와 다르면 `MDM_PROJECT_ROOT` 를 명시한다.

**훅이 판정하는 저장소.** 플러그인 훅은 플러그인이 켜진 **모든** 저장소에서 돈다(사용자 범위로 설치했으면 전부).
1.x 에서는 훅 파일이 키트 프로젝트에만 복사돼 있었으므로, 같은 범위를 지키려고 훅은 키트 프로젝트 표식
**`docs/status/STATUS.md`** 가 있을 때만 판정하고 없으면 통과한다. 정직한 한계: 표식을 지우면 훅이 꺼진다 —
1.x 에서 훅 파일을 지우면 꺼지던 것과 같은 신뢰 수준이고, 그 수준은 규칙 11(훅 우회 금지)과 `/mdm:review` 가 다룬다.
표식은 `hooks/lib-root.sh` 가 `MDM_PROJECT_ROOT` → `CLAUDE_PROJECT_DIR` → 현재 디렉토리에서 출발해 **git 최상위까지 위로** 찾는다 —
제품 하위 디렉토리에서 띄운 세션은 `CLAUDE_PROJECT_DIR` 가 그 하위 경로이기 때문이다(실측). 단 `/mdm:init` 이 쓰는 **프로젝트 범위** 등록은
`.claude/settings.json` 을 세션 시작 디렉토리에서만 읽으므로(Claude Code 동작) 하위 디렉토리 세션에는 플러그인 자체가 켜지지 않는다 —
**제품 루트에서 세션을 연다.** 훅이 실제로 이렇게 판정하는지는 원본 저장소 `scripts/test-hooks.sh` 가 재고, 우회는 K2 리뷰가 재현한다.

## 파일 소유권 — 설치·업그레이드의 기준 ★

| 구분 | 파일 | 업그레이드 시 |
|---|---|---|
| **플러그인 제공** (제품에 복사되지 않음) | 커맨드 · 서브에이전트 · 훅 · 검사 엔진 · 런처 | `/plugin update` 가 통째로 갈아 준다. 제품 저장소는 변하지 않는다 |
| **키트 소유** (제품에 심지만 내용은 키트가 만든다) | `CLAUDE.md`(§6 고유 규칙 제외) · `AGENTS.md` · `docs/guides/` 전체 · `docs/index.md` · `docs/MOC.md` · `docs/{upstream,spec,quality,status}/index.md` 와 `*/archive/index.md` · 템플릿(`C00-`·`ST-000-`·`ADR-000-`) | `mdm init --upgrade` 가 새 판으로 교체 (`CLAUDE.md` 는 `.dev-kit-new` 사이드카) |
| **생성물** (형상 관리 제외) | `docs/reports/*.html` — 매번 다시 만들어진다. 정본은 md 다 | 무시 |
| **프로젝트 소유** (증거·산출물) | `docs/spec/*`의 내용(`source-map.md` 포함) · `docs/upstream/`의 스냅샷과 `manifest.tsv` · `docs/plan/`의 사이클·Story·roadmap 내용 · **`docs/plan/index.md` 「사이클 현황」 표**와 **`docs/decisions/index.md` 「목록」 표** · `docs/quality/*`의 기록 · `docs/status/STATUS.md` 와 `docs/status/archive/` 의 기록 · `docs/decisions/`의 ADR · `docs/meta/` · `docs/evidence/` · `.github/workflows/mdm-check.yml`(심은 뒤에는 프로젝트 것 — `MDM_KIT_REF` 핀도 프로젝트가 올린다) · `.claude/` 전체(설정·이 저장소 자신의 커맨드) | **절대 덮어쓰지 않는다** |

> **`.claude/settings.json` 은 프로젝트 소유지만 두 키만 더한다** — `extraKnownMarketplaces.my-dev-method` 와
> `enabledPlugins."mdm@my-dev-method"`. 이미 다른 값이 있으면 덮지 않고 알린다. 1.x 의 `.dev-kit` 사이드카·hooks 항목 병합은 없어졌다.
>
> **`docs/plan/index.md`·`docs/decisions/index.md` 는 0.7.0 에서 프로젝트 소유로 내려왔다.**
> 그 두 표에 사이클 현황 행·ADR 목록 행이 실리고 정합성 검사 I 가 그것을 정본으로 보기 때문이다.
> 대가: 그 파일의 핵심 원칙 문단은 업그레이드로 자동 갱신되지 않는다 — CHANGELOG 의 「양식 변경」을 따라 옮겨 적는다.

`docs/upstream/`의 스냅샷은 프로젝트가 소유하지만 **손으로 고치지 않는다** — 정본은 상류에 있고,
고치면 `mdm check` 가 해시로 잡아 실패시킨다.

## 업그레이드 (이미 키트를 쓰는 저장소)

1. `/plugin update mdm@my-dev-method` (또는 `/plugin marketplace update my-dev-method`) — 커맨드·훅·엔진이 새 판이 된다. 세션을 다시 시작한다.
2. 제품 저장소에서 `/mdm:init --upgrade` — 키트 소유 문서만 교체하고 `CLAUDE.md.dev-kit-new` 를 남긴다.
3. `CLAUDE.md` 첫 줄 스탬프로 이전 버전을 확인하고, 원본 저장소의 `CHANGELOG.md`에서 그 이후의 **「양식 변경」**을 읽어
   프로젝트 소유 파일을 새 양식으로 **옮겨 적는다.** `CLAUDE.md` 는 새 판으로 교체한 뒤 프로젝트명과 §6 고유 규칙을 되살린다.
4. `.github/workflows/mdm-check.yml` 에 `MDM_KIT_REF` 가 **있으면** 새 버전(`v2.0.0` 형식)으로 올린다.
   **없으면**(1.x 양식이거나 직접 쓴 CI) 올릴 핀이 없다 — 설치기가 옆에 둔 `mdm-check.yml.dev-kit-new` 로 교체하고
   (이 저장소가 더한 단계는 옮겨 적는다) 사이드카를 지운다. **로컬 플러그인과 CI 엔진이 다른 판이면 판정이 갈린다** —
   `mdm doctor` 의 `ci_pin_matches`(핀 없는 CI 는 `false`)·`ci_legacy`(옛 엔진 경로를 부르는가)가 둘을 대조한다.
5. `/hooks` 로 훅 등록을 확인하고, STATUS 최근 결정에 업그레이드 사실을 한 줄 남긴다.

**키트를 쓴 적 없는 저장소에 `--upgrade` 를 쓰지 않는다** — `docs/index.md`·`docs/MOC.md`·`AGENTS.md` 등을 키트 판으로 교체한다(issues #229·#428). 신규 설치가 중단되면 그 이유를 먼저 본다.

### 1.x 에서 올라오기 (복사 방식 → 플러그인) ★

1.x 배포본은 `.claude/{commands,agents,hooks,scripts}` 와 `.claude/README.md`·`settings.json` 의 hooks 항목을 제품에 복사했다.
그대로 두면 **옛 `/mdm-adopt` 와 새 `/mdm:adopt` 가 함께 뜨고**, 옛 훅이 옛 엔진(`.claude/scripts/`)으로 한 번 더 돈다 — 정본이 둘이 된다.

`mdm init --upgrade` 는 그 파일들을 **찾아서 분류해 알리기만 한다** (기본). 분류의 근거는 **내용 해시**다:
`scripts/legacy-manifest.tsv` 에 0.3.0~1.0.0 각 판이 배포한 `.claude/` 파일의 sha256 이 있고,

- **원본과 바이트 단위로 같은 파일** → 키트 것이 확실하다. `--retire-legacy` 를 주면 `*.dev-kit-1x-retired` 로 개칭하고(지우지 않는다),
  그 훅 파일의 `settings.json` 등록만 뺀다.
- **이름은 키트 옛 이름인데 내용이 다른 파일** → 이 저장소가 고쳤거나 이 저장소 것이다. **어느 경우에도 건드리지 않는다.**
  파일을 열어 판단한 뒤 사람이 처리한다 — 키트의 옛 판이 맞으면 같은 방식으로 개칭한다:

  ```bash
  mv .claude/commands/mdm-adopt.md .claude/commands/mdm-adopt.md.dev-kit-1x-retired    # 지우지 말고 접미사를 붙인다 — `.md` 로 끝나지 않으면 등록에서 빠진다
  ```

  `.claude/commands` 가 공용 디렉토리를 가리키는 **심볼릭 링크**면 그 디렉토리의 파일이 바뀐다 — 먼저 확인해라.

> **왜 기본이 「알리기만」인가.** 0.7.0 개명 때 자동 이관을 두 판 만들었고 리뷰가 둘 다 치명으로 잡았다 —
> 설치기는 「이 파일이 키트 것인가」를 추측했고, 두 판 모두 리뷰가 치명으로 잡아 걷어냈다(1판은 프로젝트 자기 파일을 지웠고, 2판은 버전 가드가 실제 경로에서 닫히지 않았다)(2026-08-27 사용자 결정: 설치기는 옛 이름을 건드리지 않는다).
> 내용 해시는 추측이 아니지만, 그 결정을 바꾸는 것은 사용자 몫이라 **옵트인 플래그**로만 둔다 — 2026-09-11 사용자가 이 플래그를 승인했다.
> 이 분류가 실제로 그렇게 동작하는지는 원본 저장소 `scripts/test-install-upgrade.sh` 가 잰다.

**CI 도 같이 바꾼다.** 1.x 의 `.github/workflows/mdm-check.yml` 은 `bash .claude/scripts/mdm-check.sh` 한 줄이고 `MDM_KIT_REF` 가 없다 —
올릴 핀이 없다. 설치기가 옆에 둔 `mdm-check.yml.dev-kit-new`(2.0.0 양식)로 **먼저 교체한 뒤** `--retire-legacy` 를 쓴다.
순서를 뒤집으면 물린 `.claude/scripts/mdm-check.sh` 를 CI 가 부르다 그 순간 깨진다 (`mdm doctor` 의 `ci_legacy: true` 가 그 상태다).

물린 파일을 확인하고 지웠다면 **문서에 남은 옛 이름 참조도 함께 고친다** — `/mdm-adopt` → `/mdm:adopt`, `mdm-code-review` → `mdm:code-review`,
`.claude/scripts/check-consistency.sh` → `mdm check`, `python3 .claude/scripts/mdm-contract.py …` → `mdm contract …`. `mdm ops refs` 가 제품 문서(`docs/**/*.md`·`CLAUDE.md`)의 백틱 경로 참조를 **첫 건에서 멈추며 한 건씩** 알린다 — 이름 참조(`/mdm-adopt`)와 `.github/workflows` 는 대상 밖이라 `grep -rn '\.claude/scripts\|/mdm-' docs CLAUDE.md .github` 로 함께 찾는다.

## Claude Code 밖에서 (CI · 다른 에이전트)

검사 엔진은 커맨드가 아니라 스크립트라서 어디서든 돈다. 원본 저장소를 받아 런처를 부른다 — 제품 CI 양식이 정확히 이렇게 한다:

```bash
git clone --depth 1 --branch v2.0.0 https://github.com/JIM00N/my_dev_method.git "$RUNNER_TEMP/mdm"
MDM_PROJECT_ROOT="$PWD" bash "$RUNNER_TEMP/mdm/plugins/mdm/bin/mdm" final
```

엔진을 제품 작업 트리 **밖**에 두는 이유: 인계·실행 증거가 제품의 파일 집합을 해시하므로 안에 두면 그 파일들이 섞인다.
다른 에이전트(Codex 등)는 `AGENTS.md` 로 규칙을 읽고 같은 방식으로 `mdm check` 를 돌린다. 훅·커맨드·서브에이전트는 Claude Code 에서만 동작한다.

## 이 키트가 강제하는 것

| 문제 | 이 키트의 장치 | 강제 방식 |
|---|---|---|
| **계획 문서 여러 장이 서로 어긋난 채 구현 시작** | S0 도입의 교차 대조 | 절차 |
| **유저플로우를 상태 전이표로 착각 → 에이전트가 상태를 지어냄** | S0 계약 확인 (전이표는 어느 도구도 안 담는다) | 절차 |
| **검증 조건 5개짜리 요구사항이 테스트 1개로 완료됨** | 매핑표 `조건 수` 칸 — 수용 기준별 현재 실행 증거 | **스크립트** |
| **계획 도구가 없어서 시작을 못 함** | `/mdm:plan` — 압박 → 묶어 묻기 → 작성 → 검증. 외부 의존 0 | 절차 |
| **답이 없는 칸을 남긴 채 구현 시작 → 에이전트가 지어냄** | `/mdm:ready` — Story 슬롯 12칸을 AI가 채우고 갈리는 것만 질문 | **절차** (12칸 판정 JSON의 구조·근거와 입력 해시를 검사하며 의미는 사람이 판정) |
| 그 판정을 안 하고 사이클을 연다 | 매핑표 `준비` 칸이 진행 중인데 미달(빈 칸·`❌`·재판정)이면 실패 | **스크립트** (판정 기록과 현재 계약 해시를 대조) |
| **Story가 커서 한 에이전트가 감당 못 함 → 영향 범위가 번짐** | `/mdm:ready` 2단계 크기 판정 — 트리거 하나·종료 상태 하나가 될 때까지 나눈다 | 절차 |
| **도메인 규칙("거부하면 어디까지 막나")이 저장될 곳이 없음** | `domain.md` 5절 비즈니스 규칙 표 (규칙 · 어기면 무슨 일이) | 절차 |
| **md 를 사람이 읽기 어려워 판정을 미룸** | `mdm report` — 판정할 것이 많은 4시점에 HTML 한 장 | 절차 |
| **같은 것이 상류와 저장소에 두 벌로 생겨 갈라짐** | S0 계약 확인이 정본 소유권을 판정 | 절차 |
| **어느 요구사항 근거로 만드는지 추적 불가** | `docs/spec/source-map.md`의 요구사항 ID·화면 ID 추적 | **스크립트** |
| **구현 중 문서-코드 정합이 깨짐** | 고아 인용·미커버 요구사항·화면 불일치·참조 깨짐 검사 | **스크립트** |
| **상류가 바뀐 것을 모른 채 계속 지음** | `/mdm:adopt --sync` → 재검토 표시 → 처리 전까지 검사 실패 | **스크립트** |
| AI가 뭘 만들지 모른 채 코딩 시작 | S1~S4 설계 단계 + 각 단계 DoD | 절차 |
| **계획이 요구사항에서 멈춰 세부가 구현 시점에 지어내짐** | `/mdm:plan`의 요구사항 → 기능 → 사양 세 층 + 사양별 영향 영역·선행 (**검사 J**) | **스크립트** (`/mdm:plan` 경로) · 절차 (외부 상류) |
| **누가 무엇을 할 수 있나가 늦게 정해져 화면·데이터를 다시 짬** | 계획 2절 역할 × 권한 표 (거부 경로 포함, **검사 J**) — 갭이면 `docs/spec/domain.md` 4절 | **스크립트** (`/mdm:plan` 경로) · 절차 (외부 상류) |
| 세션이 끊기면 맥락 소실 | `docs/status/STATUS.md` 활성 스냅샷 1장 + 유형별 archive + 현재 파일 집합에 묶인 인계 기록 | **훅 · 스크립트** |
| "완료했습니다"의 실체 없음 | 단계별 완료 조건(DoD) + 실행 가능한 검사 명령 + 수용 기준별 JUnit 실행 증거 | 절차 · **스크립트** |
| **초록불을 위해 테스트·타입 검사를 약화** | 절대 규칙 11 + `code-conventions.md` 5-1 + `/mdm:review` | **서브에이전트** |
| 회귀를 아무도 못 잡음 | S6 3절 TDD (RED → GREEN) | 절차 |
| 수동 검수가 사이클이 늘수록 죽음 | S6 5-4 — 버그 잡은 시나리오는 자동 테스트로 승격 | 절차 |
| 버그가 기록 없이 사라짐 | `docs/quality/issues.md` 강제 기록 | 절차 |
| 같은 실수 반복 | 공통 원인·실패 통제·적용 조건 검토 후 `rules-learned.md` 규칙 승격 (`/mdm:ingest-errors`) | **서브에이전트** |
| AI가 기술을 임의 선택 | `docs/spec/stack.md` 사전 확정 (설치 명령·매니페스트 편집 감시) | **훅** |
| 비밀값이 저장소에 들어감 | 커밋(`-a` 포함)·파일 쓰기 시점 검사 | **훅** |
| 로컬과 CI 가 다른 엔진으로 판정 | 제품 CI 의 `MDM_KIT_REF` 핀 ↔ 플러그인 버전 · 핀 없는 1.x CI 는 설치기가 양식 사이드카로 교체 안내 | 진단 (`mdm doctor` 의 `ci_pin_matches`·`ci_legacy` — 사람이 읽는다. 검사를 실패시키지 않는다) |
| 코드 품질·명명·검사 기준이 프로젝트마다 흔들림 | S4의 `docs/spec/code-conventions.md` + 실행 가능한 검사 명령 | 절차 |
| 계층 문서를 AI가 안 읽음 | `CLAUDE.md`의 **상황별 라우팅 표** | 절차 |
| 한 번에 다 만들려다 붕괴 | `docs/plan/cycles/` 사이클 분할 | 절차 |
| 병렬 작업이 같은 파일을 덮어씀 | `docs/plan/stories/` 영향 범위·권한 계약 | 절차 |
| spec/이 시간이 갈수록 소설이 됨 | 사이클 종료 시 스펙 드리프트 대조 (`/mdm:cycle-close`) | 절차 |
| 절차가 프로젝트 크기에 비해 과함 | 프로파일 → **각 가이드 DoD의 프로파일 표식** | 절차 |
| 문서가 시간이 갈수록 비대해짐 | 파일별 상한·이동처·실행 주체 (STATUS 200줄 등) | 절차·훅 |

**훅**은 산문이 아니라 실제로 막힌다. **스크립트**는 문서 정합성을 기계로 확정한다.
**서브에이전트**는 구현과 분리된 컨텍스트로 판단이 필요한 것만 본다.

## 단계 개요

| 단계 | 이름 | 산출물 | 스킵 조건 |
|---|---|---|---|
| **S0** | **도입 — 계획 문서 찾아 받아들이기** | `docs/upstream/` · `docs/spec/source-map.md` | 없음 — 모든 프로젝트의 진입점 |
| (S0 분기) | 계획이 없을 때 — 키트가 직접 만든다 (`/mdm:plan`) | `docs/upstream/plan.md` (요구사항 → 기능 → 사양 · 권한 표) | 계획 문서를 찾았으면 스킵 |
| S1 | 문제·범위 정의 | `docs/spec/product.md` (+ 프로파일 판정) | 없음 |
| S2 | 도메인·데이터·상태 | `docs/spec/domain.md` | 저장할 데이터가 없으면 축약 |
| S3 | 인터페이스 설계 | `docs/spec/interface.md` | 없음 (형태만 달라짐) |
| S4 | 구조·스택·안정성 | `docs/spec/stack.md`, `docs/spec/architecture.md`, `docs/spec/code-conventions.md` | 없음 |
| S5 | 시각 설계 | `docs/spec/ui.md` | **화면이 없으면 스킵** (Lite는 화면이 있어도 스킵 가능) |
| S6 | 구축·검수·배포 | 코드, 테스트, `docs/quality/*` | 없음 |

**S0를 지나면 S1~S5를 처음부터 밟지 않는다.** S0의 **계약 확인이 `❌ 갭`으로 판정한 절만** 편다 —
대체로 S2 ②③④(데이터·상태 전이표·권한 표)와 S4 2·4부(스택·검사 명령·안정성)다.
계획 도구가 담지 않는 것들이고, **정확히 그것이 훅과 코드리뷰의 연료**다.
다만 **무엇이 갭인지는 상류마다 다르므로 단정하지 않고 확인한다** — 권한·데이터를 담아 주는 도구도 있다.

S1~S4는 **설계**다. 여기 품질이 전체를 결정하므로 추론을 가장 높게 쓴다 (Claude Code `ultrathink`, Codex reasoning effort `high` 이상).
S5~S6은 **구현**이다. 모드가 인터뷰에서 "구현 → `/mdm:review` → 검수 요청 → 피드백 → 수정 반복"으로 바뀐다.

절차량은 프로파일이 정한다. 단, **어느 프로파일에서도 줄이지 않는 것**이 있다 — `docs/guides/profiles.md`.
