# my_dev_method — AI 협업 개발방법론

AI 에이전트와 함께 소프트웨어를 개발할 때, **빠른 첫 구현보다 올바른 결정·권한·검증 증거·재사용 가능한 학습**을 남기기 위한 방법론입니다.

이 저장소에는 제품 코드가 없습니다. 제품별 PRD, 코드, 비밀값, 실행 로그는 각 제품의 로컬 저장소가 소유합니다.

## 구성

```text
README.md                   방법론의 목적과 적용 경계
templates/dev-kit/          프로젝트에 복사해 쓰는 실행 템플릿 (.claude/ 강제 장치 포함)
guides/                     범용 해설 (현재 비어 있음 — 절차의 단일 기준은 templates/dev-kit/docs/guides/)
examples/first-pilot/       첫 적용을 검증하는 체크리스트
CHANGELOG.md                방법론 자체의 변경 이력
```

## 핵심 흐름

```text
목적·성공 기준·비목표
→ 난이도 사분면 → 프로파일(Lite/Standard/Full) 판정
→ S1~S4 설계
→ Story / 권한 영향 계약
→ 작은 TDD 구현 사이클 (RED → GREEN → REFACTOR)
→ /review 코드리뷰 (code-review 서브에이전트 — 검증 우회·드리프트 적발)
→ 로컬 검증 + 사람 검수
→ 버그를 잡은 시나리오는 자동 테스트로 승격
→ 오류 즉시 기록
→ Error Learning Agent 인제스트
→ 스펙 드리프트 대조
→ Main 통합·archive
```

## 적용 원칙

- 목적·범위·권한·중요 위험을 바꾸지 않는 질문은 하지 않습니다.
- 새롭고 되돌리기 어려운 결정은 학습 모드로, 이미 배운 기본값은 실행 모드로 진행합니다.
- **절차량은 프로파일이 정합니다.** 개인 도구에 대규모 절차를 요구하면 방법론이 통째로 버려집니다.
- **초록불을 만들기 위해 검증을 약화시키지 않습니다.** 테스트 삭제·단언 완화·타입 무시·예외 삼킴은 통과가 아닙니다.
- 서비스 페르소나의 권한과 개발 에이전트의 작업 권한을 분리합니다. Story 문서가 그 계약입니다.
- 병렬 구현은 데이터·권한·API·코드 컨벤션·파일 소유권이 확정된 뒤에만 합니다.
- 산문 규칙은 드리프트하므로, 지킬 수 있는 것은 **훅으로 강제**하고, 훅이 못 잡는 것(검증 우회·학습 승격)은 **별도 서브에이전트 컨텍스트**가 잡습니다.
- 코드리뷰와 에러 학습은 구현 에이전트가 아니라 전용 서브에이전트(`/review`, `/ingest-errors`)가 수행합니다. 사람은 결과의 반영 판단만 합니다.
- `index.md`는 문서 카탈로그, `MOC.md`는 탐색 허브입니다. 이 구분은 최상위에서만 유지합니다.
- 제품 코드·테스트·서비스 실행은 제품의 **로컬 개발 환경**에서만 합니다.

## 빠른 시작

1. 이 저장소를 클론합니다.
2. `scripts/install-kit.sh <제품 저장소 경로>`를 실행합니다 — `CLAUDE.md`·`AGENTS.md`·`docs/`·`.claude/`가 복사되고,
   기존 `.claude/`가 있으면 통째로 덮지 않고 병합합니다(`settings.json`은 보존). 이미 키트를 쓰는 저장소는 `--upgrade`로
   키트 소유 파일만 교체합니다. 손으로 하는 절차는 [templates/dev-kit/README.md](templates/dev-kit/README.md) 참조.
3. `CLAUDE.md`의 프로젝트 이름·설명을 바꾸고 `docs/status/STATUS.md`를 시작 상태로 기록합니다.
4. `docs/guides/S1-problem.md`부터 시작합니다. 사분면을 정한 직후 `docs/guides/profiles.md`로 프로파일을 판정합니다.
5. 코드 작성 전 S4에서 `stack.md`, `architecture.md`, `code-conventions.md`를 확정하고, 품질 검사 명령을 실제로 한 번 실행합니다.
6. 첫 Story는 TDD로 구현하고, 구현 덩어리마다 `/review`로 코드리뷰를 받습니다. 테스트·오류·검수 증거는 **제품 저장소**의 `docs/quality/`에 남기고,
   방법론이 유용했는지에 대한 **회고만** 이 저장소의 `examples/first-pilot/` 양식으로 가져옵니다.

상세 적용법은 [templates/dev-kit/README.md](templates/dev-kit/README.md)를 참조하세요.
