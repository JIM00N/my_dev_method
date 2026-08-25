# <프로젝트명>

<한 줄 설명>

이 파일은 **라우팅만** 한다. 구체적 지시는 `docs/` 하위에 있다.
**200줄 이하 하드 제한** — 길어지면 `docs/index.md`(카탈로그), `docs/MOC.md`(탐색 허브), 하위 가이드로 옮긴다. `docs/status/STATUS.md`도 같은 200줄 이하 하드 제한을 지킨다.

---

## 0. 세션 시작 시 (예외 없음)

1. `docs/status/STATUS.md`를 읽는다 — 지금 어느 단계이고 무엇이 열려 있는지.
2. STATUS가 가리키는 **현재 단계 가이드 1개**를 읽는다 (`docs/guides/S<n>-*.md`).
3. 그 가이드가 "입력"으로 지정한 문서만 추가로 읽는다.

`docs/` 전체를 한 번에 읽지 않는다. 위 3단계로 좁혀서 읽는다.

## 1. 상황별 라우팅 표 ★

| 이런 상황이면 | 반드시 읽고 | 반드시 쓴다 |
|---|---|---|
| 세션 시작 / 뭘 할지 모를 때 | `docs/status/STATUS.md` | — |
| 새 단계에 진입할 때 | `docs/guides/S<n>-*.md` | 해당 `docs/spec/*.md` |
| 새 기술·권한·구조 결정을 할 때 | `docs/guides/decision-modes.md` | `docs/spec/stack.md` 또는 ADR |
| 코드를 한 줄이라도 쓰기 전 | `docs/spec/stack.md`, `docs/spec/architecture.md`, `docs/spec/code-conventions.md` | — |
| 새 기능·사이클을 시작할 때 | `docs/plan/roadmap.md` | `docs/plan/cycles/C<nn>-*.md` |
| 버그·리뷰 지적을 발견했을 때 | `docs/quality/index.md` | `docs/quality/issues.md` (즉시 기록) |
| 새 에러 기록을 종합·학습할 때 | `docs/guides/error-learning-ingest.md` | `docs/quality/learning-log.md` 및 필요한 규칙·검수 문서 |
| 검수를 시작할 때 | `docs/quality/test-scenarios.md` | `docs/quality/issues.md` |
| 같은 유형 문제가 2번째일 때 | `docs/quality/issues.md` | `docs/quality/rules-learned.md` |
| 되돌리기 어려운 선택을 할 때 | `docs/decisions/index.md` | `docs/decisions/ADR-<nnn>-*.md` |
| 작업을 끝낼 때 (매번) | — | `docs/status/STATUS.md` |
| 업무 자동화·AX 프로젝트일 때 | `docs/guides/addons/business-automation.md` | — |

문서 카탈로그는 `docs/index.md`, 문서 관계 MOC는 `docs/MOC.md`. 상태 카탈로그는 `docs/status/index.md`, 상태 MOC는 `docs/status/MOC.md`.

## 2. 절대 규칙

1. **계획에 없는 것을 만들지 않는다.** 좋아 보이는 기능이 떠오르면 구현하지 말고 `docs/plan/roadmap.md`의 백로그에 적는다.
2. **DoD를 못 채우면 다음 단계로 넘어가지 않는다.** 각 가이드 말미의 완료 조건 체크리스트가 통과 기준이다.
3. **"완료했습니다"라고 말하기 전에** 해당 DoD 체크리스트를 실제로 대조한다. 대조하지 않은 완료 보고는 금지.
4. **기술 스택을 임의로 고르지 않는다.** `docs/spec/stack.md`에 없는 라이브러리·서비스를 도입하려면 먼저 사용자에게 선택지와 근거를 제시하고 승인받는다.
5. **에러는 발생할 때마다 기록 후 고친다.** `docs/quality/issues.md`에 먼저 적고 수정한다. 새 기록은 별도 Error Learning Agent가 종합·인제스트한다. 기록 없이 고치면 재발 패턴이 보이지 않는다.
6. **검수 없이 배포하지 않는다.** `docs/quality/test-scenarios.md`의 시나리오를 사람이 통과시킨 뒤에만 배포한다.
7. **한 번에 끝까지 만들지 않는다.** 사이클(MVP) 단위로 자른다 — 구축 → 검수 → 안정화 → 배포 → 다음 사이클.
8. **과설계를 잘라낸다.** 스스로 제안한 것이 요구사항보다 크면 축소안을 함께 제시한다.
9. **작업 종료 시 `docs/status/STATUS.md`를 갱신한다.** 갱신하지 않은 채 세션을 끝내지 않는다. 해결된 항목을 STATUS에 누적하지 말고 유형별 archive로 옮긴다.
10. **모르면 묻는다.** 추측으로 스펙을 채우지 말고 사용자에게 인터뷰로 확인한다.

## 3. 진행 상태 어휘 (고정)

`⬜ 대기` · `🔵 진행 중` · `🟡 검수 대기` · `✅ 완료` · `⛔ 막힘`

이 5개만 쓴다. `docs/status/STATUS.md`와 사이클 문서가 이 어휘로 집계된다.

## 4. 단계 지도

| 단계 | 이름 | 가이드 | 산출물 |
|---|---|---|---|
| S1 | 문제·범위 정의 | `docs/guides/S1-problem.md` | `docs/spec/product.md` |
| S2 | 도메인·데이터·상태 | `docs/guides/S2-domain.md` | `docs/spec/domain.md` |
| S3 | 인터페이스 설계 | `docs/guides/S3-interface.md` | `docs/spec/interface.md` |
| S4 | 구조·스택·안정성 | `docs/guides/S4-architecture.md` | `docs/spec/stack.md`, `docs/spec/architecture.md` |
| S5 | 시각 설계 | `docs/guides/S5-ui.md` | `docs/spec/ui.md` |
| S6 | 구축·검수·배포 | `docs/guides/S6-build.md` | 코드, `docs/quality/*` |

- **S1~S4는 설계다.** 높은 추론 설정으로, 사용자를 **인터뷰**해서 채운다.
- **S5~S6은 구현이다.** 모드를 "검수 요청 → 피드백 → 수정 반복"으로 전환한다.
- 화면이 없는 프로젝트(라이브러리·CLI·백엔드 전용)는 **S5를 스킵**하고 S3에서 API·명령 표면을 설계한다.
- 이 6단계는 최초 구축에만 쓰는 게 아니라 **기능을 확장할 때마다 다시 밟는다** (범위만 작아진다).

## 5. 프로젝트 고유 규칙

<!-- 이 프로젝트에만 해당하는 규칙을 여기 적는다. 5개를 넘으면 docs/ 하위 문서로 옮긴다. -->

- (없음)
