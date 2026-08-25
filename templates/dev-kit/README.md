# dev-kit — AI 개발 지시서 템플릿

AI(Claude Code / Codex 등)와 함께 소프트웨어를 개발할 때 쓰는 **범용 지시서 + 문서 골격** 세트.
`my_dev_method` 저장소가 원본이며, 대상 프로젝트 저장소에 복사해서 쓰는 배포본이다.

## 설치

```bash
# 프로젝트 저장소 루트에서
cp /경로/my_dev_method/templates/dev-kit/CLAUDE.md .
cp /경로/my_dev_method/templates/dev-kit/AGENTS.md .
cp -R /경로/my_dev_method/templates/dev-kit/docs .
```

복사 후 할 일:

1. `CLAUDE.md` 상단의 `<프로젝트명>`, `<한 줄 설명>` 치환 (`AGENTS.md`는 호환용 진입점으로 그대로 둠)
2. `docs/status/STATUS.md`에 시작 시점 기록 → 현재 단계를 `S1`로
3. 업무 자동화·AX 컨설팅 프로젝트면 `CLAUDE.md`의 애드온 줄 주석 해제
4. S4에서 `docs/spec/code-conventions.md`를 해당 기술 스택의 실제 검사 명령과 규칙으로 확정
5. AI에게: `"CLAUDE.md를 읽고 S1부터 시작해. 나를 인터뷰해서 진행해."`

## 이 키트가 강제하는 것

| 문제 | 이 키트의 장치 |
|---|---|
| AI가 뭘 만들지 모른 채 코딩 시작 | S1~S4 설계 단계 + 각 단계 DoD |
| 세션이 끊기면 맥락 소실 | `docs/status/STATUS.md` 활성 스냅샷 1장 + 유형별 archive |
| "완료했습니다"의 실체 없음 | 단계별 완료 조건(DoD) 체크리스트 |
| 버그가 기록 없이 사라짐 | `docs/quality/issues.md` 강제 기록 |
| 같은 실수 반복 | 2회 재발 시 `rules-learned.md` 규칙 승격 |
| AI가 기술을 임의 선택 | `docs/spec/stack.md` 사전 확정 |
| 코드 품질·명명·검사 기준이 프로젝트마다 흔들림 | S4의 `docs/spec/code-conventions.md` + 실행 가능한 검사 명령 |
| 계층 문서를 AI가 안 읽음 | `CLAUDE.md`의 **상황별 라우팅 표** |
| 한 번에 다 만들려다 붕괴 | `docs/plan/cycles/` 사이클 분할 |
| STATUS·AGENTS가 시간이 갈수록 비대해짐 | 두 파일 200줄 이하 + `docs/index.md`/영역 MOC + 유형별 archive |

## 6단계 개요

| 단계 | 이름 | 산출물 | 스킵 조건 |
|---|---|---|---|
| S1 | 문제·범위 정의 | `spec/product.md` | 없음 |
| S2 | 도메인·데이터·상태 | `spec/domain.md` | 저장할 데이터가 없으면 축약 |
| S3 | 인터페이스 설계 | `spec/interface.md` | 없음 (형태만 달라짐) |
| S4 | 구조·스택·안정성 | `spec/stack.md`, `spec/architecture.md`, `spec/code-conventions.md` | 없음 |
| S5 | 시각 설계 | `spec/ui.md` | **화면이 없으면 스킵** |
| S6 | 구축·검수·배포 | 코드 + `quality/` | 없음 |

S1~S4는 **설계**다. 여기 품질이 전체를 결정하므로 높은 추론 설정을 쓴다.
S5~S6은 **구현**이다. 모드가 인터뷰에서 "검수 요청 → 피드백 → 수정 반복"으로 바뀐다.

## 출처

정석 강의 6단계 방법론을 범용 소프트웨어 개발용으로 일반화한 것.
업무 병목 분석·ROI 산출 등 자동화 대시보드 특유의 절차는 `docs/guides/addons/business-automation.md`로 분리했다.

원본 저장소: `JIM00N/my_dev_method` · 방법론 해설: `guides/` 및 `examples/`
