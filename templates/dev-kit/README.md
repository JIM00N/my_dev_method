# dev-kit — AI 개발 지시서 템플릿

AI(Claude Code / Codex 등)와 함께 소프트웨어를 개발할 때 쓰는 **범용 지시서 + 문서 골격 + 강제 장치** 세트.
`my_dev_method` 저장소가 원본이며, 대상 프로젝트 저장소에 복사해서 쓰는 배포본이다.

## 설치

```bash
# 프로젝트 저장소 루트에서
cp /경로/my_dev_method/templates/dev-kit/CLAUDE.md .
cp /경로/my_dev_method/templates/dev-kit/AGENTS.md .
cp -R /경로/my_dev_method/templates/dev-kit/docs .
cp -R /경로/my_dev_method/templates/dev-kit/.claude .
chmod +x .claude/hooks/*.sh
```

복사 후 할 일:

1. `CLAUDE.md` 상단의 `<프로젝트명>`, `<한 줄 설명>` 치환 (`AGENTS.md`는 호환용 진입점으로 그대로 둠)
2. `docs/status/STATUS.md`에 시작 시점 기록 → 현재 단계를 `S1`로
3. 업무 자동화·AX 컨설팅 프로젝트면 `CLAUDE.md`의 애드온 줄 주석 해제
4. S1에서 사분면을 정한 직후 `docs/guides/profiles.md`로 **프로파일(Lite/Standard/Full)** 판정
5. S4에서 `docs/spec/code-conventions.md`를 해당 기술 스택의 실제 검사 명령과 규칙으로 확정하고, **그 명령을 한 번 실행해 본다**
6. AI에게: `"CLAUDE.md를 읽고 S1부터 시작해. 나를 인터뷰해서 진행해."` (또는 `/stage 1`)

## 이 키트가 강제하는 것

| 문제 | 이 키트의 장치 | 강제 방식 |
|---|---|---|
| AI가 뭘 만들지 모른 채 코딩 시작 | S1~S4 설계 단계 + 각 단계 DoD | 절차 |
| 세션이 끊기면 맥락 소실 | `docs/status/STATUS.md` 활성 스냅샷 1장 + 유형별 archive | **훅** |
| "완료했습니다"의 실체 없음 | 단계별 완료 조건(DoD) + 실행 가능한 검사 명령 | 절차 |
| **초록불을 위해 테스트·타입 검사를 약화** | 절대 규칙 11 + `code-conventions.md` 5-1 금지된 우회 | 절차·리뷰 |
| 회귀를 아무도 못 잡음 | S6 3절 TDD (RED → GREEN) | 절차 |
| 수동 검수가 사이클이 늘수록 죽음 | S6 5-4 — 버그 잡은 시나리오는 자동 테스트로 승격 | 절차 |
| 버그가 기록 없이 사라짐 | `docs/quality/issues.md` 강제 기록 | 절차 |
| 같은 실수 반복 | 2회 재발 시 `rules-learned.md` 규칙 승격 | 절차 |
| AI가 기술을 임의 선택 | `docs/spec/stack.md` 사전 확정 | **훅** |
| 비밀값이 저장소에 들어감 | 커밋 전 스테이징 검사 | **훅** |
| 코드 품질·명명·검사 기준이 프로젝트마다 흔들림 | S4의 `docs/spec/code-conventions.md` + 실행 가능한 검사 명령 | 절차 |
| 계층 문서를 AI가 안 읽음 | `CLAUDE.md`의 **상황별 라우팅 표** | 절차 |
| 한 번에 다 만들려다 붕괴 | `docs/plan/cycles/` 사이클 분할 | 절차 |
| 병렬 작업이 같은 파일을 덮어씀 | `docs/plan/stories/` 영향 범위·권한 계약 | 절차 |
| spec/이 시간이 갈수록 소설이 됨 | 사이클 종료 시 스펙 드리프트 대조 | 절차 |
| 절차가 프로젝트 크기에 비해 과함 | `docs/guides/profiles.md` Lite/Standard/Full | 절차 |
| STATUS·AGENTS가 시간이 갈수록 비대해짐 | 두 파일 200줄 이하 + 폴더별 `index.md` + 유형별 archive | 절차 |

**훅**으로 표시된 것은 산문이 아니라 실제로 막힌다. 상세는 `.claude/README.md`.

## 6단계 개요

| 단계 | 이름 | 산출물 | 스킵 조건 |
|---|---|---|---|
| S1 | 문제·범위 정의 | `spec/product.md` (+ 프로파일 판정) | 없음 |
| S2 | 도메인·데이터·상태 | `spec/domain.md` | 저장할 데이터가 없으면 축약 |
| S3 | 인터페이스 설계 | `spec/interface.md` | 없음 (형태만 달라짐) |
| S4 | 구조·스택·안정성 | `spec/stack.md`, `spec/architecture.md`, `spec/code-conventions.md` | 없음 |
| S5 | 시각 설계 | `spec/ui.md` | **화면이 없으면 스킵** |
| S6 | 구축·검수·배포 | 코드, 테스트, `quality/` | 없음 |

S1~S4는 **설계**다. 여기 품질이 전체를 결정하므로 추론을 가장 높게 쓴다 (Claude Code `ultrathink`, Codex reasoning effort `high` 이상).
S5~S6은 **구현**이다. 모드가 인터뷰에서 "검수 요청 → 피드백 → 수정 반복"으로 바뀐다.

절차량은 프로파일이 정한다. 단, **어느 프로파일에서도 줄이지 않는 것**이 있다 — `docs/guides/profiles.md`.

## 출처

정석 강의 6단계 방법론을 범용 소프트웨어 개발용으로 일반화한 것.
업무 병목 분석·ROI 산출 등 자동화 대시보드 특유의 절차는 `docs/guides/addons/business-automation.md`로 분리했다.

원본 저장소: `JIM00N/my_dev_method` · 방법론 해설: `guides/` 및 `examples/`
