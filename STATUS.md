# STATUS — my_dev_method

**최종 갱신**: 2026-09-11
**프로파일**: Lite
**출시 스탬프**: 2.0.0 (플러그인 전환 — 커밋·`v2.0.0` 태그·푸시 사용자 승인 2026-09-11)
**기준 커밋**: 5c2dd53 (v1.0.0) 위의 작업 트리
**현재 작업**: 키트를 Claude Code 플러그인 `mdm@my-dev-method` 로 전환 — 사용자 지시 「이 방법론은 plugin으로 발전시키자」(2026-09-11)

## 2.0.0 플러그인 전환 — 2026-09-11

- **구조:** `templates/dev-kit/` → `plugins/mdm/`. 커맨드 `commands/*.md`(`/mdm:adopt` 등, `/mdm:init` 신규), 에이전트 `agents/*.md`
  (`mdm:code-review`·`mdm:error-learning`), `hooks/hooks.json` + 훅 3 + 공용 `hooks/lib-root.sh`, 런처 `bin/mdm`, 엔진 `scripts/`
  (`mdm_env.py`·`init-project.sh`·`legacy-manifest.tsv` 신규), 제품 양식 `templates/`. 루트 `.claude-plugin/marketplace.json`.
- **실측한 전제:** `claude -p --plugin-dir` 로 커맨드 본문 `${CLAUDE_PLUGIN_ROOT}` 치환 · 플러그인 `bin/` 의 Bash PATH 등록 ·
  `hooks.json` 실행을 확인했다. Bash 도구 환경에는 `CLAUDE_PROJECT_DIR` 가 없고, 하위 디렉토리에서 연 세션의 `CLAUDE_PROJECT_DIR` 는 그 하위 경로다.
- **설치기:** `/mdm:init`(`mdm init`)은 문서 골격 + `.claude/settings.json` 플러그인 등록만 심는다. 1.x 잔재는 내용 해시로 분류해 알린다(기본 불간섭).
- **훅:** 표식 `docs/status/STATUS.md` 를 git 최상위까지 위로 찾고, 없으면 판정하지 않는다.
- **제품 CI:** `MDM_KIT_REF` 핀으로 원본을 clone 해 `bin/mdm final`. 핀 없는 1.x CI 옆에는 양식 사이드카를 둔다.
- 워크플로 아티팩트 페이지를 2.0.0 으로 갱신했다(설치 절·`/mdm:` 이름·`mdm check`·1회전).

## 커밋 전 독립 리뷰 — 1회전

- 6축 전부 실행(대규모 변경). K2 는 첫 인스턴스가 10분 무진행으로 실패해 좁혀 재실행했다.
  사용자 지시로 진행 중이던 K2·반증 6개를 Opus 로 다시 띄웠다.
- 높음 7건 제기 → 반증: 확정 3(죽은 회귀 테스트 · 런처 fixture 부재 · 1.x CI 안내 단절) · 강등 3 · 선재로 집계 제외 1.
  **회전 판정은 실패**(확정 높음 3) — 셋 다 fixture 를 먼저 만들어 RED 를 본 뒤 고쳤다. 강등·선재 4건도 이번에 고쳤다.
  재리뷰는 하지 않는다(1회전 규칙). 수정 뒤 남은 치명·높음 없음.
- 보통·낮음 34건 기록. 문서·설치기 실패 경로는 고쳤고, 검사 11·12 fixture 공백 등은 사유와 함께 미뤘다. 상세는 로컬 issues #424~#458.

## 검증

- CI 와 같은 9종: check-docs · review-gate · consistency · unittest 41 · report · docs-check 47 · install-upgrade 49 · hooks 15 · launcher 16.
- `claude plugin validate` 통과(플러그인·마켓). 새 fixture 는 전부 수정 전 RED 를 확인했다.
- 측정하지 않은 것: 실제 마켓플레이스 설치 경로(`/plugin marketplace add JIM00N/my_dev_method`) — 커밋·푸시·태그 뒤에야 가능하다.

## 다음 3가지

1. 푸시 뒤 원격 CI(docs-check 9종)가 통과하는지 확인한다. 제품 CI 양식과 `AGENTS.md` 는 `v2.0.0` 태그를 clone 한다.
2. 실제 마켓플레이스 설치로 새 제품 저장소에서 `/mdm:init` → `/mdm:adopt` 를 한 번 밟는다.
3. 미룬 fixture 공백(issues #441·#442·#444·#445·#448)과 기존 관찰(#418~#423)을 후속에서 정리한다.

## 사용자 결정 — 2026-09-11

- **#437** `--retire-legacy` 옵트인 플래그 **유지** — 사용자 승인. 0.7.0 결정(「설치기는 옛 이름을 건드리지 않는다」)은 기본 동작으로 남고,
  원본과 바이트 단위로 같은 파일의 개칭만 사람이 플래그를 줄 때 한다. 내용이 다른 파일은 어느 경우에도 건드리지 않는다.
- 2.0.0 커밋 · `v2.0.0` 태그 · 푸시 승인 — 이 STATUS 가 그 커밋에 들어간다.

## 한계와 후속

- 플러그인 로드·PATH·훅 실행은 개발 중과 리뷰 중 실측이고 CI 가 재현하지 않는다(Claude Code 가 CI 에 없다).
- 프로젝트 범위 등록은 세션 시작 디렉토리의 `.claude/settings.json` 에서만 읽힌다 — 제품 루트에서 세션을 연다.
- 훅 표식 게이트는 표식을 지우면 꺼진다 — 1.x 에서 훅 파일을 지우면 꺼지던 것과 같은 신뢰 수준.
- 이전 항목: 슬롯 근거의 의미·승인의 진실성·JUnit 생산자의 신뢰성은 해시가 증명하지 않는다. 원격 doctor 는 classic branch protection 만.

## 과거 기록

2026-09-09 V1.0.0 릴리스·2026-09-08 개선 설계·5088617 기준 구현은 `docs/history/STATUS-2026-09-09.md` 에 보존했다.
2026-08-29 까지는 `docs/history/STATUS-2026-08-29.md`. 이슈 상세는 로컬 issues.md, 공개 변경은 `CHANGELOG.md`.
