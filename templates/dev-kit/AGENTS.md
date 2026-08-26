# AGENTS

이 프로젝트의 에이전트 실행 규칙은 `CLAUDE.md`가 단일 기준이다.

1. 먼저 `CLAUDE.md`를 읽는다.
2. 이어서 `docs/status/STATUS.md`와 그 파일이 가리키는 현재 단계 가이드를 읽는다.
3. `AGENTS.md`와 `CLAUDE.md`가 충돌하면 `CLAUDE.md`를 따른다.

이 파일은 호환용 진입점이며 **200줄 이하 하드 제한**을 지킨다. 상세 절차는 `CLAUDE.md`, 문서 카탈로그는 `docs/index.md`, 문서 관계 탐색은 `docs/MOC.md`를 따른다.

`CLAUDE.md`의 규칙 중 4·9·12는 `.claude/hooks/`가 기계적으로 강제하고, 규칙 11은 `code-review` 서브에이전트(`/review`)가 잡는다. 훅이 막으면 우회하지 말고 막힌 이유를 해결한다. 이 강제 장치는 Claude Code에서만 동작하므로, 다른 에이전트로 작업할 때는 해당 규칙을 스스로 지켜야 한다.
