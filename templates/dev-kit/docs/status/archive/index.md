# status archive — 과거 상태 카탈로그·탐색

현재 판단에 필요하지 않은 상태 기록만 보관한다. 활성 상태는 항상 `docs/status/STATUS.md`에 둔다.
**현재 상태가 아니라 "왜 과거에 막혔고 어떻게 해소했는지"를 찾을 때** 이 폴더로 온다.

- `blockers/` — 해결된 차단요인: 발생 배경, 영향 Story/사이클, 해소 방법, 재발·재확인 조건
- `snapshots/` — 큰 단계 또는 사이클 종료 시점의 STATUS 사본: 날짜·전환 이유를 파일명에 포함

완료 사이클·Story·품질 이슈·큰 결정은 이 폴더에 넣지 않는다. 각각 `docs/plan/archive/`, `docs/quality/archive/`, `docs/decisions/`가 소유한다.

하위 유형 폴더는 첫 항목을 아카이브할 때 만든다. 파일명 예: `2026-08-24-resolved-play-console-blocker.md`, `2026-08-24-S4-complete.md`.

과거 기록을 현재 STATUS로 되살려 넣지 않는다. 필요하면 여기서 원문을 읽는다.
