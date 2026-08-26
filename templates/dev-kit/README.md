# dev-kit — AI 개발 지시서 템플릿

**버전: 0.3.0** (각 배포본의 버전은 `CLAUDE.md` 첫 줄의 `<!-- dev-kit v… -->` 스탬프로 확인한다)

AI(Claude Code / Codex 등)와 함께 소프트웨어를 개발할 때 쓰는 **범용 지시서 + 문서 골격 + 강제 장치** 세트.
`my_dev_method` 저장소가 원본이며, 대상 프로젝트 저장소에 복사해서 쓰는 배포본이다.

## 파일 소유권 — 설치·업그레이드의 기준 ★

| 구분 | 파일 | 업그레이드 시 |
|---|---|---|
| **키트 소유** (프로젝트가 내용을 만들지 않음) | `CLAUDE.md`(§6 고유 규칙 제외) · `AGENTS.md` · `.claude/` 전체 · `docs/guides/` 전체 · `docs/index.md` · `docs/MOC.md` · 각 폴더 `index.md` · 템플릿(`C00-`·`ST-000-`·`ADR-000-`) | 새 판으로 교체 |
| **프로젝트 소유** (증거·산출물) | `docs/spec/*`의 내용 · `docs/plan/`의 사이클·Story·roadmap 내용 · `docs/quality/*`의 기록 · `docs/status/*` · `docs/decisions/`의 ADR | **절대 덮어쓰지 않는다** |

## 설치 (처음 적용하는 저장소)

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

1. `CLAUDE.md` 상단의 `<프로젝트명>`, `<한 줄 설명>` 치환 (`AGENTS.md`는 호환용 진입점으로 그대로 둠)
2. `docs/status/STATUS.md`에 시작 시점 기록 → 현재 단계를 `S1`로
3. `jq` 설치 확인 (`jq --version`) — 없으면 guard 훅 2개가 경고만 남기고 통과한다
4. 업무 자동화·AX 컨설팅 프로젝트면 `CLAUDE.md`의 애드온 줄 주석 해제
5. S1에서 사분면을 정한 직후 `docs/guides/profiles.md`로 **프로파일(Lite/Standard/Full)** 판정
6. S4에서 `docs/spec/code-conventions.md`를 해당 기술 스택의 실제 검사 명령과 규칙으로 확정하고, **그 명령을 한 번 실행해 본다**
7. AI에게: `"CLAUDE.md를 읽고 S1부터 시작해. 나를 인터뷰해서 진행해."` (또는 `/stage 1`)

## 업그레이드 (이미 키트를 쓰는 저장소)

`cp -R docs .`를 다시 실행하지 않는다 — 프로젝트가 쌓아온 spec·이슈·STATUS·ADR이 전부 파괴된다.

1. `CLAUDE.md` 첫 줄 스탬프로 현재 버전을 확인한다.
2. 원본 저장소의 `CHANGELOG.md`에서 그 버전 이후의 변경을 읽는다.
3. **키트 소유 파일만** 새 판으로 교체한다 (위 표). `CLAUDE.md`는 교체 후 프로젝트명과 §6 고유 규칙을 되살린다.
4. 프로젝트 소유 파일은 CHANGELOG가 양식 변경을 명시한 경우에만, 기존 내용을 새 양식으로 **옮겨 적는다.**
5. `/hooks`로 훅 등록을 확인하고, STATUS의 최근 결정에 업그레이드 사실을 한 줄 남긴다.

## 이 키트가 강제하는 것

| 문제 | 이 키트의 장치 | 강제 방식 |
|---|---|---|
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

**훅**은 산문이 아니라 실제로 막힌다. **서브에이전트**는 구현과 분리된 컨텍스트가 잡는다. 상세는 `.claude/README.md`.

## 6단계 개요

| 단계 | 이름 | 산출물 | 스킵 조건 |
|---|---|---|---|
| S1 | 문제·범위 정의 | `docs/spec/product.md` (+ 프로파일 판정) | 없음 |
| S2 | 도메인·데이터·상태 | `docs/spec/domain.md` | 저장할 데이터가 없으면 축약 |
| S3 | 인터페이스 설계 | `docs/spec/interface.md` | 없음 (형태만 달라짐) |
| S4 | 구조·스택·안정성 | `docs/spec/stack.md`, `docs/spec/architecture.md`, `docs/spec/code-conventions.md` | 없음 |
| S5 | 시각 설계 | `docs/spec/ui.md` | **화면이 없으면 스킵** (Lite는 화면이 있어도 스킵 가능) |
| S6 | 구축·검수·배포 | 코드, 테스트, `docs/quality/*` | 없음 |

S1~S4는 **설계**다. 여기 품질이 전체를 결정하므로 추론을 가장 높게 쓴다 (Claude Code `ultrathink`, Codex reasoning effort `high` 이상).
S5~S6은 **구현**이다. 모드가 인터뷰에서 "구현 → `/review` → 검수 요청 → 피드백 → 수정 반복"으로 바뀐다.

절차량은 프로파일이 정한다. 단, **어느 프로파일에서도 줄이지 않는 것**이 있다 — `docs/guides/profiles.md`.

## 출처

정석 강의 6단계 방법론을 범용 소프트웨어 개발용으로 일반화한 것.
업무 병목 분석·ROI 산출 등 자동화 대시보드 특유의 절차는 `docs/guides/addons/business-automation.md`로 분리했다.

원본 저장소: `JIM00N/my_dev_method` · 방법론 해설: 원본 저장소의 `guides/` 및 `examples/`
