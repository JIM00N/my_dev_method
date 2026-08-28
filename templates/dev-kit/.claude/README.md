# .claude — 기계적 강제 계층

`CLAUDE.md`의 규칙은 산문이고, 세션이 길어지면 에이전트는 드리프트한다.
이 폴더는 **드리프트해도 막히는 것**만 담는다. 규칙과 훅이 어긋나면 규칙이 아니라 훅이 실제 동작이다.

## 구성

| 경로 | 무엇 | 대응하는 규칙 |
|---|---|---|
| `settings.json` | 훅 등록 (Bash + Write/Edit 양쪽 경로) | — |
| `hooks/status-updated.sh` | 작업 트리에 변경이 있는데 STATUS의 "최종 갱신"이 오늘이 아니면 **세션 종료를 막는다** | 절대 규칙 9 |
| `hooks/guard-dependency.sh` | `stack.md` 결정 표의 "선택" 열에 없는 패키지의 설치·매니페스트 편집을 **막는다** | 절대 규칙 4 |
| `hooks/guard-secrets.sh` | 비밀 파일·비밀값 형태 문자열의 `git commit`(`-a`·같은 명령의 `git add` 대상 포함)과 형상 관리 대상 파일 쓰기를 **막는다** | 절대 규칙 12 · S4 4부 |
| `scripts/check-consistency.sh` | 문서 정합성 기계 검사 **9종(A~I)** — 상류 스냅샷 무결성·요구사항 커버리지·테스트 실재·상류 변경 재검토 잔존·고아 ID 인용·화면 정합·참조 깨짐·**마일스톤 배치**·**문서 등재 대조** | `docs/spec/source-map.md` |
| `agents/mdm-code-review.md` | 변경분 리뷰 전용 서브에이전트 — 4축 17검사: 규칙 위반(우회·드리프트·스택) · 보안(신뢰 경계·주입·남의 것 접근·노출) · 의도치 않은 동작(되돌릴 수 없는 행동·중복 실행·실패 모드·경합·한도) · 검증 (코드는 못 고친다) | 절대 규칙 11 |
| `agents/mdm-error-learning.md` | 에러 종합·인제스트 전용 서브에이전트 (코드는 못 고친다) | `docs/guides/error-learning-ingest.md` |
| `commands/mdm-adopt.md` | `/mdm-adopt [--sync]` — 계획 문서 찾기·도입·재동기화 (**진입점**) | `docs/guides/S0-adopt.md` |
| `commands/mdm-plan.md` | `/mdm-plan` — 계획이 없을 때 키트가 직접 만든다 | `docs/guides/plan.md` |
| `commands/mdm-ready.md` | `/mdm-ready` — 준비도 점검 (Story 슬롯 12칸: AI 초안 → **크기 판정** → 갈리는 것만 질문) | `docs/guides/ready.md` |
| `scripts/report.py` | md 를 읽어 보기 쉬운 HTML 한 장으로 (검사 아님) | `docs/reports/` |
| `commands/mdm-stage.md` | `/mdm-stage [n]` — 단계 진입 | `CLAUDE.md` §0 |
| `commands/mdm-review.md` | `/mdm-review` — 1단계 정합성 검사 + 2단계 코드리뷰 위임 | `docs/guides/S6-build.md` 3-4 |
| `commands/mdm-cycle-close.md` | `/mdm-cycle-close` — 사이클 종료 점검 | `docs/guides/S6-build.md` 8절 |
| `commands/mdm-ingest-errors.md` | `/mdm-ingest-errors` — 학습 인제스트 | `docs/guides/S6-build.md` 6-3 |

## 설치 확인

```bash
claude          # 세션에서 /hooks 로 등록 상태 확인
jq --version    # 훅 2개(guard-*)는 jq가 필요하다
```

훅 스크립트는 실행 권한(755)이 커밋되어 있어 `cp -R`로 복사하면 그대로 유지된다.
`jq`가 없으면 두 guard 훅은 **stderr로 경고를 남기고 통과한다**(차단하지 않는다). 강제를 원하면 `jq`를 설치한다.

## 이름 규칙 — `mdm-` 접두 (0.7.0)

**이 키트가 넣는 커맨드·서브에이전트는 전부 `mdm-` 으로 시작한다.** `mdm` 은 이 방법론 키트의
원본 저장소 이름(`my_dev_method`)이다. `/plan`·`/review`·`/stage` 같은 흔한 이름을 그대로 쓰면
그 저장소가 이미 쓰던 커맨드나 다른 플러그인이 넣는 커맨드와 겹쳐 **어느 쪽이 뜨는지 알 수 없고**,
키트 문서가 "`/review` 를 돌린다"고 적어도 그 문장이 키트의 것을 가리킨다는 보장이 사라진다.
그래서 이름 공간 하나를 통째로 차지하는 쪽을 골랐다.

- **`mdm-` 으로 시작하지 않는 이름은 이 저장소의 것이다.** 키트는 그것을 지우지도 덮지도 않는다 —
  0.7.0 개명에서 자리를 비운 옛 이름(`adopt.md`·`review.md` 등)도 **설치기가 건드리지 않는다.**
  찾아서 알리기만 하고, 처리는 원본 저장소 `templates/dev-kit/README.md` 「업그레이드」 4-1 에서
  **사람이** 한다 — 그 파일이 키트 것인지 이 저장소 것인지는 스크립트가 알 수 없기 때문이다.
- 이 저장소가 자기 커맨드를 만들 때는 **`mdm-` 을 쓰지 않는다** — 다음 키트 업그레이드가 같은 이름을 넣는다.
- 원본 저장소는 이 규칙을 문서가 아니라 검사로 지킨다 (`check-docs.py` 검사 11).

## 설계 원칙

- **실패 시 통과, 단 침묵하지 않는다.** 훅이 판단하지 못하는 상황(도구 없음, git 저장소 아님, 파싱 실패)에서는 통과시키되, 검사를 건너뛴 사실은 경고로 남긴다. 훅이 작업을 막는 원인이 되면 그날로 꺼진다.
- **비밀값은 출력하지 않는다.** `guard-secrets.sh`는 파일명과 건수만 알린다.
- **오탐이 반복되면 훅을 끄지 말고 좁힌다.** 끄면 규칙이 산문으로 되돌아간다.
- **같은 조건으로 두 번 연속 막지 않는다.** `status-updated.sh`는 루프 차단기를 갖는다 — 만족 불가능한 조건에 에이전트를 가두지 않는다.
- 훅은 규칙 4·9·12만 강제한다. 규칙 11(검증 우회 금지)은 `mdm-code-review` 서브에이전트(`/mdm-review` 2단계)와 `docs/spec/code-conventions.md` 5-1이 잡는다.
- **정합성은 스크립트가, 판단은 서브에이전트가.** `check-consistency.sh`는 훅이 아니라 스크립트다 —
  매 도구 호출마다 돌면 비싸고, 구현 도중에는 일시적으로 어긋나는 게 정상이기 때문이다.
  대신 `/mdm-review` 1단계·사이클 시작·`/mdm-cycle-close`·CI에서 돈다. **MCP를 부르지 않으므로** 상류가 죽어도, CI에서도 돈다.
