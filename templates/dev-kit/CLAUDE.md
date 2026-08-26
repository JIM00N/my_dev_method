# <프로젝트명>

<한 줄 설명>

이 파일은 **라우팅만** 한다. 구체적 지시는 `docs/` 하위에 있다.
**200줄 이하 하드 제한** — 길어지면 `docs/index.md`(카탈로그), `docs/MOC.md`(탐색 허브), 하위 가이드로 옮긴다. `docs/status/STATUS.md`도 같은 200줄 이하 하드 제한을 지킨다.

---

## 0. 세션 시작 시 (예외 없음)

1. `docs/status/STATUS.md`를 읽는다 — 지금 어느 단계이고, 프로파일이 무엇이고, 무엇이 열려 있는지.
2. STATUS가 가리키는 **현재 단계 가이드 1개**를 읽는다 (`docs/guides/S<n>-*.md`).
3. 그 가이드가 "입력"으로 지정한 문서만 추가로 읽는다.

`docs/` 전체를 한 번에 읽지 않는다. 위 3단계로 좁혀서 읽는다.
`/stage`가 이 순서를 대신 수행한다.

## 1. 상황별 라우팅 표 ★

| 이런 상황이면 | 반드시 읽고 | 반드시 쓴다 |
|---|---|---|
| 세션 시작 / 뭘 할지 모를 때 | `docs/status/STATUS.md` | — |
| 새 단계에 진입할 때 | `docs/guides/S<n>-*.md` | 해당 `docs/spec/*.md` |
| S1에서 사분면을 확정한 직후 | `docs/guides/profiles.md` | `docs/spec/product.md` 프로파일 칸 |
| 절차가 무겁게 느껴질 때 | `docs/guides/profiles.md` | — (프로파일을 낮추지 말고 확인한다) |
| 새 기술·권한·구조 결정을 할 때 | `docs/guides/decision-modes.md` | `docs/spec/stack.md` 또는 ADR |
| 코드를 한 줄이라도 쓰기 전 | `docs/spec/stack.md`, `docs/spec/architecture.md`, `docs/spec/code-conventions.md` | — |
| 새 기능·사이클을 시작할 때 | `docs/plan/roadmap.md` | `docs/plan/cycles/C<nn>-*.md` |
| 권한 영향이 있거나 병렬로 돌릴 작업일 때 | `docs/plan/stories/ST-000-template.md` | `docs/plan/stories/ST-<nnn>-*.md` |
| 새 행동을 구현할 때 | `docs/guides/S6-build.md` 3절 | 테스트 먼저(RED) → 구현 |
| 버그·리뷰 지적을 발견했을 때 | `docs/quality/index.md` | `docs/quality/issues.md` (즉시 기록) |
| 새 에러 기록을 종합·학습할 때 | `docs/guides/error-learning-ingest.md` | `docs/quality/learning-log.md` 및 필요한 규칙·검수 문서 |
| 검수를 시작할 때 | `docs/quality/test-scenarios.md` | `docs/quality/issues.md` |
| 검수가 버그를 잡았을 때 | `docs/guides/S6-build.md` 5-4 | 그 시나리오의 자동 테스트 |
| 같은 유형 문제가 2번째일 때 | `docs/quality/issues.md` | `docs/quality/rules-learned.md` |
| 되돌리기 어려운 선택을 할 때 | `docs/decisions/index.md` | `docs/decisions/ADR-<nnn>-*.md` |
| 사이클을 닫을 때 | `docs/guides/S6-build.md` 8절 | 스펙 드리프트 대조 결과 · `docs/status/STATUS.md` |
| 작업을 끝낼 때 (매번) | — | `docs/status/STATUS.md` |
| 업무 자동화·AX 프로젝트일 때 | `docs/guides/addons/business-automation.md` | — |

문서 카탈로그는 `docs/index.md`, 문서 관계 탐색은 `docs/MOC.md`. 폴더별 카탈로그는 각 폴더의 `index.md` 하나가 맡는다.

## 2. 절대 규칙

1. **계획에 없는 것을 만들지 않는다.** 좋아 보이는 기능이 떠오르면 구현하지 말고 `docs/plan/roadmap.md`의 백로그에 적는다.
2. **DoD를 못 채우면 다음 단계로 넘어가지 않는다.** 각 가이드 말미의 완료 조건 체크리스트가 통과 기준이다.
3. **"완료했습니다"라고 말하기 전에** 해당 DoD 체크리스트를 실제로 대조한다. 대조하지 않은 완료 보고는 금지.
4. **기술 스택을 임의로 고르지 않는다.** `docs/spec/stack.md`에 없는 라이브러리·서비스를 도입하려면 먼저 사용자에게 선택지와 근거를 제시하고 승인받는다.
5. **에러는 발생할 때마다 기록 후 고친다.** `docs/quality/issues.md`에 먼저 적고 수정한다. 새 기록은 별도 `error-learning` 에이전트가 종합·인제스트한다. 기록 없이 고치면 재발 패턴이 보이지 않는다.
6. **검수 없이 배포하지 않는다.** `docs/quality/test-scenarios.md`의 시나리오를 사람이 통과시킨 뒤에만 배포한다.
7. **한 번에 끝까지 만들지 않는다.** 사이클(MVP) 단위로 자른다 — 구축 → 검수 → 안정화 → 배포 → 다음 사이클.
8. **과설계를 잘라낸다.** 스스로 제안한 것이 요구사항보다 크면 축소안을 함께 제시한다.
9. **작업 종료 시 `docs/status/STATUS.md`를 갱신한다.** 갱신하지 않은 채 세션을 끝내지 않는다. 해결된 항목을 STATUS에 누적하지 말고 유형별 archive로 옮긴다.
10. **모르면 묻는다.** 추측으로 스펙을 채우지 말고 사용자에게 인터뷰로 확인한다.
11. **초록불을 만들기 위해 검증을 약화시키지 않는다.** ★
    실패하는 테스트를 지우거나 skip하지 않는다. 단언을 느슨하게 바꾸지 않는다.
    `any`·`as`·`type: ignore`로 타입 오류를 덮지 않는다. 예외를 잡아 삼키지 않는다.
    린트를 disable 주석으로 끄지 않는다. 참조를 확인하지 않고 기존 코드를 지우지 않는다.
    스펙 항목을 조용히 빼고 완료라고 말하지 않는다.
    **막히면 `issues.md`에 적고 막혔다고 보고한다.** 초록불은 목표가 아니라 증거다.

## 3. 진행 상태 어휘 (고정)

`⬜ 대기` · `🔵 진행 중` · `🟡 검수 대기` · `✅ 완료` · `⛔ 막힘`

이 5개만 쓴다. `docs/status/STATUS.md`와 사이클 문서가 이 어휘로 집계된다.

## 4. 단계 지도

| 단계 | 이름 | 가이드 | 산출물 |
|---|---|---|---|
| S1 | 문제·범위 정의 | `docs/guides/S1-problem.md` | `docs/spec/product.md` |
| S2 | 도메인·데이터·상태 | `docs/guides/S2-domain.md` | `docs/spec/domain.md` |
| S3 | 인터페이스 설계 | `docs/guides/S3-interface.md` | `docs/spec/interface.md` |
| S4 | 구조·스택·안정성 | `docs/guides/S4-architecture.md` | `docs/spec/stack.md`, `architecture.md`, `code-conventions.md` |
| S5 | 시각 설계 | `docs/guides/S5-ui.md` | `docs/spec/ui.md` |
| S6 | 구축·검수·배포 | `docs/guides/S6-build.md` | 코드, 테스트, `docs/quality/*` |

- **S1~S4는 설계다.** 사용자를 **인터뷰**해서 채운다. 추론을 가장 높게 쓴다 —
  Claude Code는 `ultrathink`(또는 `/model`에서 상위 모델), Codex는 reasoning effort를 `high` 이상.
  여기 품질이 전체 결과를 결정하므로 토큰을 아끼지 않는다.
- **S5~S6은 구현이다.** 모드를 "검수 요청 → 피드백 → 수정 반복"으로 전환한다. 추론은 보통으로 내리되,
  원인 불명 버그·설계 변경 판단에서는 다시 올린다.
- 화면이 없는 프로젝트(라이브러리·CLI·백엔드 전용)는 **S5를 스킵**하고 S3에서 API·명령 표면을 설계한다.
- 절차량은 **프로파일**이 정한다 (`docs/guides/profiles.md`). Lite여도 테스트·기록·학습 루프는 줄이지 않는다.
- 이 6단계는 최초 구축에만 쓰는 게 아니라 **기능을 확장할 때마다 다시 밟는다** (범위만 작아진다).

## 5. 기계적 강제 장치

산문 규칙은 세션이 길어지면 드리프트한다. 아래는 **드리프트해도 막히는 것**이다. 상세는 `.claude/README.md`.

| 훅 | 무엇을 막나 | 대응 규칙 |
|---|---|---|
| `status-updated.sh` | 변경이 있는데 STATUS를 갱신하지 않은 세션 종료 | 9 |
| `guard-dependency.sh` | `stack.md`에 없는 패키지 설치 | 4 |
| `guard-secrets.sh` | 비밀값이 스테이징된 채 `git commit` | 5 |

커맨드: `/stage [n]` 단계 진입 · `/cycle-close` 사이클 종료 점검 · `/ingest-errors` 학습 인제스트
서브에이전트: `error-learning` (에러 종합 전용, 코드는 고치지 않는다)

**훅이 막았다고 우회하지 않는다.** 막힌 이유를 해결하거나 사용자에게 보고한다.

## 6. 프로젝트 고유 규칙

<!-- 이 프로젝트에만 해당하는 규칙을 여기 적는다. 5개를 넘으면 docs/ 하위 문서로 옮긴다. -->

- (없음)
