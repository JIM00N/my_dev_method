# docs MOC — 개발 문서 탐색 지도

이 파일은 문서 **관계와 탐색 경로**를 보여준다. 파일의 전체 목록·카탈로그는 `docs/index.md`가 맡는다.
폴더별 카탈로그와 폴더 안의 탐색은 각 폴더의 `index.md` **하나**가 함께 담당한다 (폴더마다 MOC를 따로 두지 않는다).

```text
현재 작업
→ status/STATUS.md
→ 현재 단계 guide
→ 해당 spec
→ 필요할 때 plan / quality / decisions
```

진입점은 하나다 — `/mdm:adopt` (S0). 계획 문서가 없으면 거기서 `/mdm:plan` 으로 갈라졌다가 S0 로 돌아온다
(`CLAUDE.md` §4 「진입점은 S0 하나다」와 같은 흐름 — issues #438):

```text
/mdm:adopt  (guides/S0-adopt.md)
→ 계획 문서를 찾는다: 저장소 안 → 밖에 있는지 묻는다 → 없으면 /mdm:plan (guides/plan.md) 이 만든다
→ upstream/ 스냅샷
→ spec/source-map.md (ID·갭)
→ 갭이 가리키는 절만 (S2·S4)
→ guides/S6-build.md
```

- 요구사항 추적: `docs/spec/source-map.md` → 요구사항 ID → 사이클 → 테스트 (검사는 `mdm check`)
- 상류 동기화: `/mdm:adopt --sync` → 재검토 표시 → 사람 판정 → `docs/spec/domain.md` 등 갱신
- 절차량 판정: `docs/spec/product.md`의 사분면 → `docs/guides/profiles.md` → 프로파일 (게이트는 각 가이드 DoD의 표식)
- 커밋 관여도: S1에서 질문 → `docs/guides/commit-policy.md` → `docs/spec/product.md`·`docs/status/STATUS.md` 커밋 정책 칸
  (**기계 장치는 없다** — 절대 규칙 13과 S1 DoD의 `(사람 확인)` 항목이 전부다)
- 설계 방법: `docs/guides/index.md` → 현재 S1~S4 가이드
- 설계 사실: `docs/spec/index.md` → source-map / product / domain / interface / stack / architecture / code-conventions / ui
- 실행 계획: `docs/plan/index.md` → roadmap → 활성 cycles → 필요하면 stories
- 현재 상태: `docs/status/index.md` → STATUS → 필요한 archive
- 품질·에러 학습: `docs/quality/index.md` → issues → error-learning-ingest guide → rules-learned → 자동 테스트 승격
- 코드리뷰: `/mdm:review` → 1단계 정합성 검사 → 2단계 `mdm:code-review` 서브에이전트 → 발견을 issues에 기록
  → 재현 테스트(RED) → 수정 (**1회전 — 재리뷰 없음**)
- 큰 결정: `docs/decisions/index.md` → ADR
- 기계적 강제: `mdm` 플러그인 → 훅·스크립트(`mdm check` 등)·커맨드(`/mdm:…`)·서브에이전트(`mdm:…`). 목록은 플러그인 README — 제품에는 복사되지 않는다. 위치는 `mdm doctor` 의 `engine` 필드(그 상위 폴더의 `README.md`), 원본은 `github.com/JIM00N/my_dev_method` 의 `plugins/mdm/README.md`

원칙: MOC는 "어디서 무엇을 찾아야 하는가", index는 "어떤 파일이 존재하는가"를 담당한다.
이 구분은 **최상위에서만** 유지한다. 하위 폴더에서 둘로 나누면 읽는 쪽이 어느 하나만 보게 되고 구분이 무너진다.
