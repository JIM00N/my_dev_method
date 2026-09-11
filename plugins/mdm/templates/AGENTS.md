# AGENTS

이 프로젝트의 에이전트 실행 규칙은 `CLAUDE.md`가 단일 기준이다.

1. 먼저 `CLAUDE.md`를 읽는다.
2. 이어서 `docs/status/STATUS.md`와 그 파일이 가리키는 현재 단계 가이드를 읽는다.
3. `AGENTS.md`와 `CLAUDE.md`가 충돌하면 `CLAUDE.md`를 따른다.

이 파일은 호환용 진입점이며 **200줄 이하 하드 제한**을 지킨다. 상세 절차는 `CLAUDE.md`, 문서 카탈로그는 `docs/index.md`, 문서 관계 탐색은 `docs/MOC.md`를 따른다.

`CLAUDE.md`의 규칙 중 4·9·12는 `mdm` 플러그인의 훅(guard-dependency · guard-secrets · status-updated)이 기계적으로 강제하고, 규칙 11은 `mdm:code-review` 서브에이전트(`/mdm:review` 2단계)가 잡는다. 훅이 막으면 우회하지 말고 막힌 이유를 해결한다. 이 강제 장치는 Claude Code에서만 동작하므로, 다른 에이전트로 작업할 때는 해당 규칙을 스스로 지켜야 한다.

**문서 정합성 검사는 커맨드가 아니라 스크립트라서 어느 에이전트에서도 돈다.** 구현 한 덩어리가 끝날 때마다, 그리고 사이클을 시작·종료할 때 직접 실행한다:

```bash
mdm check
```

`mdm` 은 dev-kit 플러그인의 `bin/mdm` 런처다. Claude Code 세션에서는 플러그인이 PATH 에 올려 준다.
다른 에이전트·터미널에서는 원본 저장소를 받아 그 런처를 직접 부른다 — 제품 CI 양식(`.github/workflows/mdm-check.yml`)이 하는 방식과 같다:

```bash
git clone --depth 1 --branch v2.0.1 https://github.com/JIM00N/my_dev_method.git /tmp/mdm
export PATH="/tmp/mdm/plugins/mdm/bin:$PATH"     # 이후 mdm check · mdm final · mdm contract … 가 돈다
```

엔진이 판정한 제품 루트는 `mdm root` 로 확인한다 (`MDM_PROJECT_ROOT` 로 고정할 수 있다).

상류 계획 문서(PRD·기능명세·유저플로우·와이어프레임)를 쓰는 프로젝트라면 요구사항 추적표는 `docs/spec/source-map.md`가 정본이다. 사이클·테스트·이슈는 그 표의 요구사항 ID·화면 ID를 인용한다 — 인용하지 않으면 무엇을 왜 만들었는지 추적되지 않고, 표에 없는 ID를 인용하면 검사가 고아 인용으로 잡는다.

운영 준비·완료는 `docs/guides/contract-evidence.md`의 파일 해시와 실행 증거를 따른다.
처음 도입 전만 --init이며 운영 통과가 아니다.

상류 전체 처리 목록·변경 위험·의미 비교·인계·동기화는 `docs/guides/operating-loop.md`를 따른다.
세션 시작에는 `mdm ops handoff-check`로 이전 인계를 읽고, 종료·CI에는 `mdm final`를 실행한다.
