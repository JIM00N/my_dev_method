# docs — 문서 카탈로그 (최상위 index)

이 프로젝트의 모든 문서 진입점. **필요한 폴더만 내려가서 읽는다.**
상황별로 무엇을 읽을지는 루트 `CLAUDE.md`의 라우팅 표가 결정한다. `AGENTS.md`는 이 규칙으로 들어오는 호환용 진입점이다. 문서 사이의 관계·탐색 흐름은 별도 `MOC.md`에 있다.

## 폴더 구성

| 폴더 | 성격 | 언제 읽나 | index |
|---|---|---|---|
| `upstream/` | **SOURCE** — 상류가 준 계획 문서 (읽기 전용 스냅샷) | 도입 시 · 상류 동기화 시 | `docs/upstream/index.md` |
| `guides/` | **HOW** — 각 단계를 어떻게 수행하는가 | 새 단계 진입 시 해당 파일 1개만 | `docs/guides/index.md` |
| `spec/` | **WHAT** — 무엇을 만드는가 (설계 산출물) | 코딩 전 · 설계 참조 시 | `docs/spec/index.md` |
| `plan/` | **WHEN** — 어떤 순서로 만드는가 | 사이클·Story 시작·종료 시 | `docs/plan/index.md` |
| `status/` | **NOW** — 지금 어디인가 | **세션 시작·종료 시 항상** | `docs/status/index.md` |
| `quality/` | 문제 기록·검수·재발 방지 | 버그 발견 · 검수 · 배포 전 | `docs/quality/index.md` |
| `decisions/` | 되돌리기 어려운 선택의 근거 | 큰 선택 전후 | `docs/decisions/index.md` |

프로젝트 루트의 `.claude/`는 문서가 아니라 **강제 장치**다 (훅·스크립트·커맨드·서브에이전트). 목록은 `.claude/README.md`.

## 읽기 우선순위

```
1순위 (항상)      status/STATUS.md
2순위 (단계별)     guides/S<n>-*.md  ← STATUS가 지목한 것 하나
3순위 (그 가이드가 요구한 것)   spec/*.md
4순위 (해당 상황일 때만)        quality/, decisions/, plan/
```

## 문서 성격 구분

- `guides/`는 **변하지 않는다** — 프로젝트가 달라져도 거의 동일한 절차서.
- `spec/`·`plan/`·`status/`·`quality/`·`decisions/`는 **이 프로젝트의 내용물**이다. 단, 활성 문서는 작게 유지하고 완료 기록은 유형별 archive로 옮긴다.
- 그래서 새 프로젝트를 시작할 때 `guides/`와 `.claude/`는 그대로 복사하고 나머지는 비운다.

## 파일 목록

문서 파일을 새로 만들면 **만든 자리에서 등재한다**: 사이클은 `docs/plan/index.md`의 사이클 현황 표에(행은 영구),
ADR은 `docs/decisions/index.md`의 목록 표에(행은 영구), Story는 `docs/status/STATUS.md`의 활성 병렬 작업 표에
(**활성 동안만** — 닫힌 Story는 행을 지우고 문서만 `docs/plan/archive/stories/`로 옮긴다).
여기 없는 새 유형의 문서면 이 카탈로그와 해당 폴더 index에 줄을 더한다.
등재 없는 문서는 다음 세션이 존재를 모른다 — 카탈로그가 낡는 것이 가장 조용한 드리프트다.
사이클·ADR·Story의 등재는 도입 후 `.claude/scripts/check-consistency.sh` 검사 I가 대조한다 —
등재 없는 문서(세 유형 다), 문서 없는 행(사이클·ADR만), archive로 닫힌 Story의 잔존 행이 실패한다.
문서 없는 Story 행은 잡지 않는다 — 프로파일에 따라 Story는 문서 없이 사이클 문서에만 존재하는 것이 정상이다.

### 최상위 탐색
- `index.md` — 파일명·경로·현재성 카탈로그
- `MOC.md` — 주제·흐름·결정·문서 관계 탐색 허브

### upstream/ — 상류 계획 문서 스냅샷 (읽기 전용)
- `index.md` — 규칙·파일 목록·수집 방법
- `prd.md` · `features.md` · `userflow.md` · `wireframe.md` — 상류 산출물 사본
- `manifest.tsv` — **기계용 수집 기록** (출처·수집시각·해시)

### guides/ — 단계별 실행 지시서
- `index.md` — 단계 목록·모드 전환·기본 프롬프트
- `S0-adopt.md` — 도입 (계획 문서 찾기 · 교차 대조 · ID 정리 · 계약 확인)
- `plan.md` — 계획이 없을 때 키트가 직접 만든다 (`/mdm-plan`) — **요구사항 → 기능 → 사양** 세 층 · 권한 표 ·
  사양별 영향 영역·선행 (검사 J가 강제한다 — `self:plan` 한정)
- `ready.md` — 준비도 점검: 답이 없는 칸을 구현 전에 찾고, **Story 크기를 판정한다** (`/mdm-ready`)
- `S1-problem.md` — 문제·범위 정의
- `S2-domain.md` — 도메인·데이터·상태 정의
- `S3-interface.md` — 인터페이스 설계
- `S4-architecture.md` — 시스템 구조·스택·안정성
- `S5-ui.md` — 시각 설계 (화면 없으면 스킵)
- `S6-build.md` — 구축·검수·배포 (TDD · 자동 테스트 승격 · 스펙 드리프트)
- `profiles.md` — 사분면 → Lite/Standard/Full 절차량 판정
- `commit-policy.md` — 커밋을 에이전트가 묻고 누를지(승인) 누르고 알릴지(보고). 사용자가 고른다
- `decision-modes.md` — 기술·권한·구조 선택의 학습/실행 모드
- `error-learning-ingest.md` — 새 에러 기록을 별도 에이전트가 종합·인제스트
- `docs/guides/addons/business-automation.md` — 업무 자동화·AX 전용 추가 절차

### spec/ — 설계 산출물
- `index.md` — 산출물 카탈로그·드리프트 규칙
- `source-map.md` — **요구사항·화면 정본 매핑표** (정본 소유권 · 계약 확인표 · 요구사항 ID·화면 ID·검증 조건 수)
- `product.md` · `domain.md` · `interface.md` · `stack.md` · `architecture.md` · `code-conventions.md` · `ui.md`

### plan/ — 계획
- `index.md` — 계획 카탈로그·원칙
- `roadmap.md` — 마일스톤 + 백로그 (상한 30건)
- `cycles/` — 사이클별 실행 계획
- `stories/` — Story별 영향 범위·권한 계약·검증 방법
- `archive/` — 완료된 사이클·Story (`archive/index.md`)

### status/ — 현재 상태
- `STATUS.md` — 세션 연속성 스냅샷 (**작업 종료 시 반드시 갱신 — 훅이 강제**)
- `index.md` — 상태 파일 카탈로그·탐색 (**STATUS는 200줄 이하**)
- `archive/` — 해결된 차단요인·과거 스냅샷

### quality/ — 품질
- `index.md` — 품질 흐름·심각도·**이슈 유형 표(정본)**
- `issues.md` — 이슈 로그
- `test-scenarios.md` — 검수 시나리오 (자동화 여부 포함)
- `rules-learned.md` — 재발 방지 규칙
- `learning-log.md` — Error Learning Agent의 인제스트 근거·결과
- `archive/index.md` — 검증 완료된 이슈의 유형별 보관

### decisions/ — 의사결정 기록
- `index.md` — ADR 목록·작성 기준
- `ADR-000-template.md` — 양식
