# my_dev_method — AI 협업 개발방법론

AI 에이전트와 함께 소프트웨어를 개발할 때, **빠른 첫 구현보다 올바른 결정·권한·검증 증거·재사용 가능한 학습**을 남기기 위한 방법론입니다.

이 저장소에는 제품 코드가 없습니다. 제품별 PRD, 코드, 비밀값, 실행 로그는 각 제품의 로컬 저장소가 소유합니다.

## 구성

```text
README.md                   방법론의 목적과 적용 경계
templates/dev-kit/          프로젝트에 복사해 쓰는 실행 템플릿
guides/                     템플릿을 보완하는 범용 가이드
examples/first-pilot/       첫 적용을 검증하는 체크리스트
CHANGELOG.md                방법론 자체의 변경 이력
```

## 핵심 흐름

```text
목적·성공 기준·비목표
→ S1~S4 설계
→ Epic / Story / 권한 영향
→ 작은 TDD 구현 사이클
→ 로컬 검증
→ 오류 즉시 기록
→ Error Learning Agent 인제스트
→ Main 통합·archive
```

## 적용 원칙

- 목적·범위·권한·중요 위험을 바꾸지 않는 질문은 하지 않습니다.
- 새롭고 되돌리기 어려운 결정은 학습 모드로, 이미 배운 기본값은 실행 모드로 진행합니다.
- 서비스 페르소나의 권한과 개발 에이전트의 작업 권한을 분리합니다.
- 병렬 구현은 데이터·권한·API·코드 컨벤션·파일 소유권이 확정된 뒤에만 합니다.
- `index.md`는 문서 카탈로그, `MOC.md`는 탐색 허브이며 서로 대체하지 않습니다.
- 제품 코드·테스트·서비스 실행은 제품의 **로컬 개발 환경**에서만 합니다.

## 빠른 시작

1. 이 저장소를 클론합니다.
2. 대상 제품 저장소 루트에 `templates/dev-kit`의 `AGENTS.md`, `CLAUDE.md`, `docs/`를 복사합니다.
3. `CLAUDE.md`의 프로젝트 이름·설명을 바꾸고 `docs/status/STATUS.md`를 시작 상태로 기록합니다.
4. `docs/guides/S1-problem.md`부터 시작합니다.
5. 코드 작성 전 S4에서 `stack.md`, `architecture.md`, `code-conventions.md`를 확정합니다.
6. 첫 Story는 TDD로 구현하고, 실제 테스트·오류·회고 결과를 `examples/first-pilot/` 양식에 기록합니다.

상세 적용법은 [templates/dev-kit/README.md](templates/dev-kit/README.md)를 참조하세요.
