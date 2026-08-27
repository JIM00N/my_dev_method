# my_dev_method — dev-kit 개발 저장소

기계적으로 강제되는 개발방법론 키트(`templates/dev-kit/`)를 만드는 저장소다.
`templates/dev-kit/CLAUDE.md`는 **배포 양식**이다 — 제품 저장소용 규칙이지, 이 저장소의 작업 규칙이 아니다.

## 세션 시작

1. `STATUS.md`를 읽는다 — 버전, 지금 하는 일, 열린 이슈.
2. 이슈 상세는 `issues.md`(로컬 전용), 공개 기록은 `CHANGELOG.md`.

## 절대 규칙

1. **변경 후 커밋 전에 `/kit-review`를 돌린다.** 코드리뷰는 서브에이전트가 한다 —
   Main이 직접 diff를 평가해 "통과"를 선언하지 않는다. 만든 컨텍스트는 자기 구멍을 보지 못한다.
   축마다 서로 다른 에이전트를 쓴다 (`.claude/commands/kit-review.md`가 정본).
   장치: **git 네이티브 pre-commit 훅**(`.githooks/pre-commit`)이 커밋될 트리가 통과 도장
   (`review-stamp.sh`, git write-tree)과 일치할 때만 커밋을 허용한다. git이 커밋 시점에 직접 돌리므로
   **명령 표기를 바꾸는 것으로는** 못 피하고(`sh -c`·서브셸·`$(...)`·백틱·함수·줄이음 6가지를
   `test-review-gate.sh`가 **실제 커밋으로** 검증한다), `<pathspec>`·`-a`·`--amend` 등 부분·대체 인덱스 모드도 막힌다.
   도장 스크립트가 없거나 실행 권한이 없어도 **차단**한다(fail-closed).
   병합 커밋은 `pre-merge-commit` 훅이 따로 막는다(git 2.24+). 활성화(클론마다 한 번): `git config core.hooksPath .githooks`.
   **게이트는 에이전트 셸에서만 건다** (`CLAUDECODE`·`AI_AGENT` 표식). 사용자가 자기 터미널에서 하는 커밋은 막지 않는다 —
   사용자는 리뷰 지적의 반영 여부를 정하는 **권한자**이지 통제 대상이 아니고, 이 게이트가 겨냥하는 것은
   "세션이 길어지면 산문 규칙이 드리프트한다"(리뷰를 잊는 에이전트) 하나다.
   **정직한 한계 (전부 정책 위반으로 다룬다)** — 이 장치가 기계로 보장하는 것은 "커밋 트리 == 도장 트리"까지다:
   ① 도장이 "리뷰가 실제로 돌았음"을 증명하지는 못한다(도장은 `--write`로 찍힌다). ② `git commit --no-verify`·
   `git -c core.hooksPath=… commit`은 훅 자체를 끈다. ③ cherry-pick·revert·rebase 재생 커밋은
   git이 차단형 pre-* 훅을 주지 않아 못 막는다(issues #028 — 보조 훅 도입은 사용자 판단 대기).
   ④ **에이전트 셸 한정 분기 자체가 우회구다** — `env -u CLAUDECODE -u AI_AGENT git commit`(또는 빈 문자열 대입)이면
   게이트가 꺼진다. 표식을 늘리면 사용자를 잘못 막을 위험이 커지므로 늘리지 않는다(#035).
   **요약: 이 게이트는 "잊고 커밋하는 것"을 막지, "작정하고 우회하는 것"은 못 막는다.**
2. **리뷰 반복은 최대 3회전이다.** 회전 세는 법·초과 시 처리는 `.claude/commands/kit-review.md` 4번이 정본이다.
   (2026-08-27 확정 — 사용자 결정)
2-1. **커밋 정책: 승인 모드.** 리뷰를 통과시킨 뒤 **묻고 답을 받아야** 커밋한다. 물을 때 무엇이 바뀌었는지·
   리뷰 결과·남은 지적을 함께 준다. **모드와 무관하게 승인받는 것**은 여기서 세지 않는다 —
   `templates/dev-kit/docs/guides/commit-policy.md`의 「어느 쪽이든 반드시 묻는 것」 표가 정본이고,
   이 저장소도 그 표를 그대로 따른다 (세는 순간 갈라진다 — 실제로 갈라졌었다: issues #041·#053).
   **이 규칙에는 기계 장치가 없다** — 규칙 1의 게이트는 "트리 == 도장"만 보고 승인 여부는 모른다.
   (키트 쪽 정본은 `templates/dev-kit/docs/guides/commit-policy.md` — 제품 저장소는 S1에서 사용자가 고른다)
3. **약속을 적으면 강제 장치를 같이 만든다.** 키트 문서에 "막는다/검사한다/강제한다"를 쓰는 순간
   그 검사가 어디 있는지(스크립트·훅·fixture)를 함께 만들거나, 못 만들면 그 문장을 약속이 아닌
   권고로 고쳐 쓴다. **구현 없는 약속이 이 저장소의 제1 결함 유형이다** (2026-08 외부 리뷰로 확인).
4. **키트 동작이 바뀌면 워크플로 아티팩트 페이지도 갱신한다** (URL은 메모리 `workflow-artifact`).
5. **작업 종료 시 `STATUS.md`를 갱신한다.**

## 리뷰 축 (정본: `.claude/commands/kit-review.md`)

K1 약속–강제 대조 · K2 우회 재현(실행 기반) · K3 셸 정확성 · K4 수명주기 경로 ·
K5 의미적 문서 정합 · K6 회귀 증거 — 치명·높음은 `kit-refute`가 반증을 시도한 뒤에만 확정된다.

## 자동 검증

- `scripts/check-docs.sh` — 키트 내부 경로·참조·문법 (CI: `.github/workflows/docs-check.yml`)
- `scripts/test-review-gate.sh` — 커밋 게이트(pre-commit 훅·도장)의 우회 차단을 실측하는 회귀 검사 (CI 연결)
- `.githooks/pre-commit`·`pre-merge-commit` — **에이전트 셸에서** 도장과 다른 트리의 커밋·병합 차단
  (절대 규칙 1의 장치, `core.hooksPath`로 활성. 사용자 커밋은 막지 않는다)
