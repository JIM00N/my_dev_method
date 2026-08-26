# docs MOC — 개발 문서 탐색 지도

이 파일은 문서 **관계와 탐색 경로**를 보여준다. 파일의 전체 목록·카탈로그는 `index.md`가 맡는다.
폴더별 카탈로그와 폴더 안의 탐색은 각 폴더의 `index.md` **하나**가 함께 담당한다 (폴더마다 MOC를 따로 두지 않는다).

```text
현재 작업
→ status/STATUS.md
→ 현재 단계 guide
→ 해당 spec
→ 필요할 때 plan / quality / decisions
```

- 절차량 판정: `spec/product.md`의 사분면 → `guides/profiles.md` → 프로파일
- 설계 방법: `guides/index.md` → 현재 S1~S4 가이드
- 설계 사실: `spec/index.md` → product / domain / interface / stack / architecture / code-conventions / ui
- 실행 계획: `plan/index.md` → roadmap → 활성 cycles → 필요하면 stories
- 현재 상태: `status/index.md` → STATUS → 필요한 archive
- 품질·에러 학습: `quality/index.md` → issues → error-learning-ingest guide → rules-learned → 자동 테스트 승격
- 큰 결정: `decisions/index.md` → ADR
- 기계적 강제: `../.claude/README.md` → 훅·커맨드·서브에이전트

원칙: MOC는 "어디서 무엇을 찾아야 하는가", index는 "어떤 파일이 존재하는가"를 담당한다.
이 구분은 **최상위에서만** 유지한다. 하위 폴더에서 둘로 나누면 읽는 쪽이 어느 하나만 보게 되고 구분이 무너진다.
