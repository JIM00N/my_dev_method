# dev-kit — AI 개발 지시서 템플릿

**버전: 0.6.0** (각 배포본의 버전은 `CLAUDE.md` 첫 줄의 `<!-- dev-kit v… -->` 스탬프로 확인한다)

AI(Claude Code / Codex 등)와 함께 소프트웨어를 개발할 때 쓰는 **범용 지시서 + 문서 골격 + 강제 장치** 세트.
`my_dev_method` 저장소가 원본이며, 대상 프로젝트 저장소에 복사해서 쓰는 배포본이다.

**계획을 뽑아내는 일은 상류가 한다.** 이 키트가 맡는 것은 그다음 — 이미 있는 계획 문서를 받아
**구현 중에 문서가 서로 어긋나서 생기는 오류와 일탈을 막는 것**이다.
**어떤 계획 도구도 전제하지 않는다** — `/adopt`가 저장소 안을 먼저 뒤지고, 없으면 밖에 있는지 묻고,
그래도 없으면 `/plan`이 직접 만든다. 진입점은 `/adopt` 하나다.

## 파일 소유권 — 설치·업그레이드의 기준 ★

| 구분 | 파일 | 업그레이드 시 |
|---|---|---|
| **키트 소유** (프로젝트가 내용을 만들지 않음) | `CLAUDE.md`(§6 고유 규칙 제외) · `AGENTS.md` · `.claude/` 전체 · `docs/guides/` 전체 · `docs/index.md` · `docs/MOC.md` · 각 폴더 `index.md` · 템플릿(`C00-`·`ST-000-`·`ADR-000-`) | 새 판으로 교체 |
| **생성물** (형상 관리 제외) | `docs/reports/*.html` — 매번 다시 만들어진다. 정본은 md 다 | 무시 |
| **프로젝트 소유** (증거·산출물) | `docs/spec/*`의 내용(`source-map.md` 포함) · `docs/upstream/`의 스냅샷과 `manifest.tsv` · `docs/plan/`의 사이클·Story·roadmap 내용 · `docs/quality/*`의 기록 · `docs/status/*` · `docs/decisions/`의 ADR | **절대 덮어쓰지 않는다** |

`docs/upstream/`의 스냅샷은 프로젝트가 소유하지만 **손으로 고치지 않는다** — 정본은 상류에 있고,
고치면 `.claude/scripts/check-consistency.sh`가 해시로 잡아 실패시킨다.

## 설치 (처음 적용하는 저장소)

원본 저장소의 스크립트가 아래 전체(병합 포함)를 대신 수행한다:

```bash
/경로/my_dev_method/scripts/install-kit.sh <제품 저장소 경로>            # 설치
/경로/my_dev_method/scripts/install-kit.sh <제품 저장소 경로> --upgrade  # 업그레이드
```

손으로 하려면:

```bash
# 프로젝트 저장소 루트에서
cp /경로/my_dev_method/templates/dev-kit/CLAUDE.md .
cp /경로/my_dev_method/templates/dev-kit/AGENTS.md .
cp -R /경로/my_dev_method/templates/dev-kit/docs .
cp -R /경로/my_dev_method/templates/dev-kit/.claude .
```

**이미 `.claude/`가 있는 저장소면 마지막 줄을 쓰지 않는다** — `cp -R`은 동명 파일(특히 `settings.json`)을
말없이 덮어쓴다. 대신:

```bash
cp -R /경로/dev-kit/.claude/hooks /경로/dev-kit/.claude/commands /경로/dev-kit/.claude/agents .claude/
# settings.json은 기존 파일에 dev-kit의 hooks 항목을 손으로 병합한다 (jq 또는 편집기)
```

훅 실행 권한(755)은 커밋되어 있어 `chmod`가 필요 없다.

복사 후 할 일:

1. `CLAUDE.md` 상단 첫 두 줄(제목·한 줄 설명)을 프로젝트 것으로 치환 (`AGENTS.md`는 호환용 진입점으로 그대로 둠)
2. `docs/status/STATUS.md`에 시작 시점 기록
3. `jq` 설치 확인 (`jq --version`) — 없으면 guard 훅 2개가 경고만 남기고 통과한다
4. 업무 자동화·AX 컨설팅 프로젝트면 `docs/guides/addons/business-automation.md`를 확인한다 (`CLAUDE.md` 라우팅 표에 이미 연결되어 있다)
5. **`/adopt`를 실행한다** (현재 단계 `S0`) — 계획 문서가 있든 없든 진입점은 하나다.
   저장소 안을 먼저 뒤지고, 없으면 밖에 있는지 묻고, 그래도 없으면 `/plan`으로 보내 직접 만든다.
6. 프로파일(Lite/Standard/Full) 판정 — `docs/guides/profiles.md`. 계획 문서가 사분면을 주지 않으므로 이건 거의 항상 갭이다
7. `docs/spec/code-conventions.md`를 해당 기술 스택의 실제 검사 명령과 규칙으로 확정하고, **그 명령을 한 번 실행해 본다**

## 업그레이드 (이미 키트를 쓰는 저장소)

`install-kit.sh --upgrade`가 아래 1~3을 대신 수행한다 (키트 소유만 교체, `CLAUDE.md`는 `CLAUDE.md.dev-kit-new`로 두어 수동 병합).
`cp -R docs .`를 다시 실행하지 않는다 — 프로젝트가 쌓아온 spec·이슈·STATUS·ADR이 전부 파괴된다.

1. `CLAUDE.md` 첫 줄 스탬프로 현재 버전을 확인한다.
2. 원본 저장소의 `CHANGELOG.md`에서 그 버전 이후의 변경을 읽는다.
3. **키트 소유 파일만** 새 판으로 교체한다 (위 표). `CLAUDE.md`는 교체 후 프로젝트명과 §6 고유 규칙을 되살린다.
4. 프로젝트 소유 파일은 CHANGELOG가 양식 변경을 명시한 경우에만, 기존 내용을 새 양식으로 **옮겨 적는다.**
5. `/hooks`로 훅 등록을 확인하고, STATUS의 최근 결정에 업그레이드 사실을 한 줄 남긴다.

## 이 키트가 강제하는 것

| 문제 | 이 키트의 장치 | 강제 방식 |
|---|---|---|
| **계획 문서 여러 장이 서로 어긋난 채 구현 시작** | S0 도입의 교차 대조 | 절차 |
| **유저플로우를 상태 전이표로 착각 → 에이전트가 상태를 지어냄** | S0 계약 확인 (전이표는 어느 도구도 안 담는다) | 절차 |
| **검증 조건 5개짜리 요구사항이 테스트 1개로 완료됨** | 매핑표 `조건 수` 칸 — 조건 하나당 테스트 하나 | **스크립트** |
| **계획 도구가 없어서 시작을 못 함** | `/plan` — 압박 → 묶어 묻기 → 작성 → 검증. 외부 의존 0 | 절차 |
| **답이 없는 칸을 남긴 채 구현 시작 → 에이전트가 지어냄** | `/ready` — Story 슬롯 12칸을 AI가 채우고 갈리는 것만 질문. 미달이면 못 연다 | **스크립트** |
| **Story가 커서 한 에이전트가 감당 못 함 → 영향 범위가 번짐** | `/ready` 2단계 크기 판정 — 트리거 하나·종료 상태 하나가 될 때까지 나눈다 | 절차 |
| **도메인 규칙("거부하면 어디까지 막나")이 저장될 곳이 없음** | `domain.md` 5절 비즈니스 규칙 표 (규칙 · 어기면 무슨 일이) | 절차 |
| **md 를 사람이 읽기 어려워 판정을 미룸** | `report.py` — 판정할 것이 많은 4시점에 HTML 한 장 | 절차 |
| **같은 것이 상류와 저장소에 두 벌로 생겨 갈라짐** | S0 계약 확인이 정본 소유권을 판정 | 절차 |
| **어느 요구사항 근거로 만드는지 추적 불가** | `docs/spec/source-map.md`의 요구사항 ID·화면 ID 추적 | **스크립트** |
| **구현 중 문서-코드 정합이 깨짐** | 고아 인용·미커버 요구사항·화면 불일치·참조 깨짐 검사 | **스크립트** |
| **상류가 바뀐 것을 모른 채 계속 지음** | `/adopt --sync` → 재검토 표시 → 처리 전까지 검사 실패 | **스크립트** |
| AI가 뭘 만들지 모른 채 코딩 시작 | S1~S4 설계 단계 + 각 단계 DoD | 절차 |
| 세션이 끊기면 맥락 소실 | `docs/status/STATUS.md` 활성 스냅샷 1장 + 유형별 archive | **훅** |
| "완료했습니다"의 실체 없음 | 단계별 완료 조건(DoD) + 실행 가능한 검사 명령 | 절차 |
| **초록불을 위해 테스트·타입 검사를 약화** | 절대 규칙 11 + `code-conventions.md` 5-1 + `/review` | **서브에이전트** |
| 회귀를 아무도 못 잡음 | S6 3절 TDD (RED → GREEN) | 절차 |
| 수동 검수가 사이클이 늘수록 죽음 | S6 5-4 — 버그 잡은 시나리오는 자동 테스트로 승격 | 절차 |
| 버그가 기록 없이 사라짐 | `docs/quality/issues.md` 강제 기록 | 절차 |
| 같은 실수 반복 | 2회 재발 시 `rules-learned.md` 규칙 승격 (`/ingest-errors`) | **서브에이전트** |
| AI가 기술을 임의 선택 | `docs/spec/stack.md` 사전 확정 (설치 명령·매니페스트 편집 감시) | **훅** |
| 비밀값이 저장소에 들어감 | 커밋(`-a` 포함)·파일 쓰기 시점 검사 | **훅** |
| 코드 품질·명명·검사 기준이 프로젝트마다 흔들림 | S4의 `docs/spec/code-conventions.md` + 실행 가능한 검사 명령 | 절차 |
| 계층 문서를 AI가 안 읽음 | `CLAUDE.md`의 **상황별 라우팅 표** | 절차 |
| 한 번에 다 만들려다 붕괴 | `docs/plan/cycles/` 사이클 분할 | 절차 |
| 병렬 작업이 같은 파일을 덮어씀 | `docs/plan/stories/` 영향 범위·권한 계약 | 절차 |
| spec/이 시간이 갈수록 소설이 됨 | 사이클 종료 시 스펙 드리프트 대조 (`/cycle-close`) | 절차 |
| 절차가 프로젝트 크기에 비해 과함 | 프로파일 → **각 가이드 DoD의 프로파일 표식** | 절차 |
| 문서가 시간이 갈수록 비대해짐 | 파일별 상한·이동처·실행 주체 (STATUS 200줄 등) | 절차·훅 |

**훅**은 산문이 아니라 실제로 막힌다. **스크립트**는 문서 정합성을 기계로 확정한다.
**서브에이전트**는 구현과 분리된 컨텍스트로 판단이 필요한 것만 본다. 상세는 `.claude/README.md`.

## 단계 개요

| 단계 | 이름 | 산출물 | 스킵 조건 |
|---|---|---|---|
| **S0** | **도입 — 계획 문서 찾아 받아들이기** | `docs/upstream/` · `docs/spec/source-map.md` | 없음 — 모든 프로젝트의 진입점 |
| (S0 분기) | 계획이 없을 때 — 키트가 직접 만든다 (`/plan`) | `docs/upstream/plan.md` | 계획 문서를 찾았으면 스킵 |
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
S5~S6은 **구현**이다. 모드가 인터뷰에서 "구현 → `/review` → 검수 요청 → 피드백 → 수정 반복"으로 바뀐다.

절차량은 프로파일이 정한다. 단, **어느 프로파일에서도 줄이지 않는 것**이 있다 — `docs/guides/profiles.md`.

## 출처

정석 강의 6단계 방법론을 범용 소프트웨어 개발용으로 일반화한 것.
업무 병목 분석·ROI 산출 등 자동화 대시보드 특유의 절차는 `docs/guides/addons/business-automation.md`로 분리했다.

원본 저장소: `JIM00N/my_dev_method` · 방법론 해설: 원본 저장소의 `guides/` 및 `examples/`
