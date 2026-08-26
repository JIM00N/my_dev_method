<!-- dev-kit v0.3.0 · 원본: my_dev_method/templates/dev-kit · 업그레이드 절차: 원본 저장소 templates/dev-kit/README.md -->
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
| 구현 한 덩어리가 끝났을 때 | — | `/review` 실행 (`code-review` 서브에이전트가 검토) |
| 버그·리뷰 지적을 발견했을 때 | `docs/quality/index.md` | `docs/quality/issues.md` (즉시 기록) |
| 새 에러 기록을 종합·학습할 때 | — | `/ingest-errors` 실행 (`error-learning` 서브에이전트에 위임 — Main이 직접 쓰지 않는다) |
| 검수를 시작할 때 | `docs/quality/test-scenarios.md` | `docs/quality/issues.md` |
| 검수가 버그를 잡았을 때 | `docs/guides/S6-build.md` 5-4 | 그 시나리오의 자동 테스트 |
| 같은 유형 문제가 2번째일 때 | `docs/quality/issues.md` | `/ingest-errors` 실행 (규칙 승격은 `error-learning`이 한다) |
| 되돌리기 어려운 선택을 할 때 | `docs/decisions/index.md` | `docs/decisions/ADR-<nnn>-*.md` |
| 사이클을 닫을 때 | `docs/guides/S6-build.md` 8절 | `/cycle-close` 실행 결과 · `docs/status/STATUS.md` |
| 작업을 끝낼 때 (매번) | — | `docs/status/STATUS.md` |
| 업무 자동화·AX 프로젝트일 때 | `docs/guides/addons/business-automation.md` | — |

문서 카탈로그는 `docs/index.md`, 문서 관계 탐색은 `docs/MOC.md`. 폴더별 카탈로그는 각 폴더의 `index.md` 하나가 맡는다.

## 2. 절대 규칙

1. **계획에 없는 것을 만들지 않는다.** 좋아 보이는 기능이 떠오르면 구현하지 말고 `docs/plan/roadmap.md`의 백로그에 적는다.
2. **DoD를 못 채우면 다음 단계로 넘어가지 않는다.** 각 가이드 말미의 완료 조건 체크리스트가 통과 기준이다.
   프로파일 표식(`(Standard+)`·`(Full)`)이 붙은 항목은 해당 프로파일에서만 본다 — 절차량 축약은 DoD 표식으로만 존재한다 (`docs/guides/profiles.md`).
3. **"완료했습니다"라고 말하기 전에** 해당 DoD 체크리스트를 실제로 대조한다. 대조하지 않은 완료 보고는 금지.
   `(사람 확인)` 항목은 에이전트가 대신 체크하지 않는다 — 사용자에게 요청하고 받은 답을 기록한다.
4. **기술 스택을 임의로 고르지 않는다.** `docs/spec/stack.md`에 없는 라이브러리·서비스를 도입하려면 먼저 사용자에게 선택지와 근거를 제시하고 승인받는다.
5. **에러는 발생할 때마다 기록 후 고친다.** `docs/quality/issues.md`에 먼저 적고 수정한다. 새 기록은 별도 `error-learning` 에이전트가 종합·인제스트한다. 기록 없이 고치면 재발 패턴이 보이지 않는다.
6. **검수 없이 배포하지 않는다.** `docs/quality/test-scenarios.md`의 시나리오를 사람이 통과시킨 뒤에만 배포한다.
7. **한 번에 끝까지 만들지 않는다.** 사이클(MVP) 단위로 자른다 — 구축 → 검수 → 안정화 → 배포 → 다음 사이클.
8. **과설계를 잘라낸다.** 스스로 제안한 것이 요구사항보다 크면 축소안을 함께 제시한다.
9. **작업 종료 시 `docs/status/STATUS.md`를 갱신한다.** 갱신하지 않은 채 세션을 끝내지 않는다. 해결된 항목을 STATUS에 누적하지 말고 유형별 archive로 옮긴다.
10. **모르면 묻는다.** 추측으로 스펙을 채우지 말고 사용자에게 인터뷰로 확인한다.
11. **초록불을 만들기 위해 검증을 약화시키지 않는다.** ★
    금지 목록의 정본은 `docs/spec/code-conventions.md` 5-1 표다 — 테스트 삭제·skip, 단언 완화,
    타입 오류 덮기, 예외 삼킴, 린트 disable, 참조 미확인 삭제, 스펙 항목 은폐, 훅 우회.
    **막히면 `issues.md`에 적고 막혔다고 보고한다.** 초록불은 목표가 아니라 증거다.
    리뷰는 `/review`(`code-review` 서브에이전트)가 이 표를 기준으로 잡는다.
12. **비밀값을 코드·저장소에 넣지 않는다.** 키·비밀번호·토큰은 환경 변수나 비밀값 관리 도구에 두고 코드에서는 참조만 한다.
    `.env` 류는 형상 관리에서 제외한다 (`.env.example`만 남긴다). 유출됐으면 즉시 폐기·재발급한다.

## 3. 진행 상태 어휘 (고정)

작업 상태: `⬜ 대기` · `🔵 진행 중` · `🟡 검수 대기` · `✅ 완료` · `⛔ 막힘` — 이 5개만 쓴다.
문서 머리말의 문서 상태는 별도 어휘를 쓴다: `미작성` · `작성 중` · `확정`. 두 어휘를 섞지 않는다.
`docs/status/STATUS.md`와 사이클 문서가 작업 상태 어휘로 집계된다.

## 4. 단계 지도

| 단계 | 이름 | 가이드 | 산출물 |
|---|---|---|---|
| S1 | 문제·범위 정의 | `docs/guides/S1-problem.md` | `docs/spec/product.md` |
| S2 | 도메인·데이터·상태 | `docs/guides/S2-domain.md` | `docs/spec/domain.md` |
| S3 | 인터페이스 설계 | `docs/guides/S3-interface.md` | `docs/spec/interface.md` |
| S4 | 구조·스택·안정성 | `docs/guides/S4-architecture.md` | `docs/spec/stack.md`, `docs/spec/architecture.md`, `docs/spec/code-conventions.md` |
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

## 5. 기계적 강제 장치와 서브에이전트

산문 규칙은 세션이 길어지면 드리프트한다. 아래는 **드리프트해도 막히거나, 다른 컨텍스트가 잡는 것**이다. 상세는 `.claude/README.md`.

| 훅 | 무엇을 막나 | 대응 규칙 |
|---|---|---|
| `status-updated.sh` | 변경이 있는데 STATUS를 갱신하지 않은 세션 종료 | 9 |
| `guard-dependency.sh` | `stack.md`에 없는 패키지 설치·매니페스트 편집 | 4 |
| `guard-secrets.sh` | 비밀값이 담긴 `git commit`(`-a` 포함)·파일 쓰기 | 12 |

| 서브에이전트 | 언제 | 왜 분리하나 |
|---|---|---|
| `code-review` (`/review`) | 구현 한 덩어리 끝날 때 · 사이클 닫기 전 | 구현한 컨텍스트는 자기 우회(규칙 11 위반)를 보지 못한다 |
| `error-learning` (`/ingest-errors`) | 새 에러 기록이 쌓였을 때 · 사이클 종료 시 | 구현 관점과 학습 관점을 섞으면 규칙 승격이 안 일어난다 |

커맨드: `/stage [n]` 단계 진입 · `/review` 코드리뷰 · `/cycle-close` 사이클 종료 점검 · `/ingest-errors` 학습 인제스트

**훅이 막았다고 우회하지 않는다.** 막힌 이유를 해결하거나 사용자에게 보고한다.

## 6. 프로젝트 고유 규칙

<!-- 이 프로젝트에만 해당하는 규칙을 여기 적는다. 5개를 넘으면 docs/ 하위 문서로 옮긴다. -->

- (없음)
