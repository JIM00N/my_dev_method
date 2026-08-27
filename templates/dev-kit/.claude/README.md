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
| `scripts/check-consistency.sh` | 문서 정합성 기계 검사 **8종(A~H)** — 상류 스냅샷 무결성·요구사항 커버리지·테스트 실재·상류 변경 재검토 잔존·고아 ID 인용·화면 정합·참조 깨짐·**마일스톤 배치** | `docs/spec/source-map.md` |
| `agents/code-review.md` | 변경분 리뷰 전용 서브에이전트 — 4축 17검사: 규칙 위반(우회·드리프트·스택) · 보안(신뢰 경계·주입·남의 것 접근·노출) · 의도치 않은 동작(되돌릴 수 없는 행동·중복 실행·실패 모드·경합·한도) · 검증 (코드는 못 고친다) | 절대 규칙 11 |
| `agents/error-learning.md` | 에러 종합·인제스트 전용 서브에이전트 (코드는 못 고친다) | `docs/guides/error-learning-ingest.md` |
| `commands/adopt.md` | `/adopt [--sync]` — 계획 문서 찾기·도입·재동기화 (**진입점**) | `docs/guides/S0-adopt.md` |
| `commands/plan.md` | `/plan` — 계획이 없을 때 키트가 직접 만든다 | `docs/guides/plan.md` |
| `commands/ready.md` | `/ready` — 준비도 점검 (Story 슬롯 12칸: AI 초안 → **크기 판정** → 갈리는 것만 질문) | `docs/guides/ready.md` |
| `scripts/report.py` | md 를 읽어 보기 쉬운 HTML 한 장으로 (검사 아님) | `docs/reports/` |
| `commands/stage.md` | `/stage [n]` — 단계 진입 | `CLAUDE.md` §0 |
| `commands/review.md` | `/review` — 1단계 정합성 검사 + 2단계 코드리뷰 위임 | `docs/guides/S6-build.md` 3-4 |
| `commands/cycle-close.md` | `/cycle-close` — 사이클 종료 점검 | `docs/guides/S6-build.md` 8절 |
| `commands/ingest-errors.md` | `/ingest-errors` — 학습 인제스트 | `docs/guides/S6-build.md` 6-3 |

## 설치 확인

```bash
claude          # 세션에서 /hooks 로 등록 상태 확인
jq --version    # 훅 2개(guard-*)는 jq가 필요하다
```

훅 스크립트는 실행 권한(755)이 커밋되어 있어 `cp -R`로 복사하면 그대로 유지된다.
`jq`가 없으면 두 guard 훅은 **stderr로 경고를 남기고 통과한다**(차단하지 않는다). 강제를 원하면 `jq`를 설치한다.

## 설계 원칙

- **실패 시 통과, 단 침묵하지 않는다.** 훅이 판단하지 못하는 상황(도구 없음, git 저장소 아님, 파싱 실패)에서는 통과시키되, 검사를 건너뛴 사실은 경고로 남긴다. 훅이 작업을 막는 원인이 되면 그날로 꺼진다.
- **비밀값은 출력하지 않는다.** `guard-secrets.sh`는 파일명과 건수만 알린다.
- **오탐이 반복되면 훅을 끄지 말고 좁힌다.** 끄면 규칙이 산문으로 되돌아간다.
- **같은 조건으로 두 번 연속 막지 않는다.** `status-updated.sh`는 루프 차단기를 갖는다 — 만족 불가능한 조건에 에이전트를 가두지 않는다.
- 훅은 규칙 4·9·12만 강제한다. 규칙 11(검증 우회 금지)은 `code-review` 서브에이전트(`/review` 2단계)와 `docs/spec/code-conventions.md` 5-1이 잡는다.
- **정합성은 스크립트가, 판단은 서브에이전트가.** `check-consistency.sh`는 훅이 아니라 스크립트다 —
  매 도구 호출마다 돌면 비싸고, 구현 도중에는 일시적으로 어긋나는 게 정상이기 때문이다.
  대신 `/review` 1단계·사이클 시작·`/cycle-close`·CI에서 돈다. **MCP를 부르지 않으므로** 상류가 죽어도, CI에서도 돈다.
