# quality archive — 해결된 이슈 카탈로그·탐색

열린 이슈는 `docs/quality/issues.md`에만 둔다. 재검수까지 통과한 이슈는 유형별 하위 폴더에 보관한다.
**과거 에러의 원인·해결·재검수 근거를 찾을 때만** 이 폴더로 온다. 재사용할 예방 규칙은 `docs/quality/rules-learned.md`에 있다.

폴더명은 `docs/quality/index.md` 유형 표(정본)의 archive 폴더 열을 그대로 쓴다.
`learning-log/`는 학습 로그의 오래된 종합 보관용이다. 하위 폴더는 **첫 항목을 아카이브할 때 만든다** (`mkdir -p`).

각 보관 이슈에는 재현 절차, 전제 조건, 원인, 조치, 재검수 근거, 재발 방지 규칙 링크, **그 시나리오를 자동 테스트로 승격했는지 여부**를 남긴다. 같은 유형이 두 번째면 `docs/quality/rules-learned.md`에도 승격한다.
