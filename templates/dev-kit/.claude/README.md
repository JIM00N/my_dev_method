# .claude — 기계적 강제 계층

`CLAUDE.md`의 규칙은 산문이고, 세션이 길어지면 에이전트는 드리프트한다.
이 폴더는 **드리프트해도 막히는 것**만 담는다. 규칙과 훅이 어긋나면 규칙이 아니라 훅이 실제 동작이다.

## 구성

| 경로 | 무엇 | 대응하는 규칙 |
|---|---|---|
| `settings.json` | 훅 등록 (Bash + Write/Edit 양쪽 경로) | — |
| `hooks/status-updated.sh` | 작업 트리에 변경이 있는데 STATUS의 "최종 갱신"이 오늘이 아니면 **세션 종료를 막는다** | 절대 규칙 9 |
| `hooks/guard-dependency.sh` | `stack.md` 결정 표의 "선택" 열에 없는 패키지의 설치·매니페스트 편집을 **막는다** | 절대 규칙 4 |
| `hooks/guard-secrets.sh` | 비밀 파일·비밀값 형태 문자열의 `git commit`(`-a` 포함)과 형상 관리 대상 파일 쓰기를 **막는다** | 절대 규칙 12 · S4 4부 |
| `agents/code-review.md` | 변경분 리뷰 전용 서브에이전트 — 검증 우회·스펙 드리프트·스택 위반을 잡는다 (코드는 못 고친다) | 절대 규칙 11 |
| `agents/error-learning.md` | 에러 종합·인제스트 전용 서브에이전트 (코드는 못 고친다) | `docs/guides/error-learning-ingest.md` |
| `commands/stage.md` | `/stage [n]` — 단계 진입 | `CLAUDE.md` §0 |
| `commands/review.md` | `/review` — 코드리뷰 위임 | `docs/guides/S6-build.md` 3-4 |
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
- 훅은 규칙 4·9·12만 강제한다. 규칙 11(검증 우회 금지)은 `code-review` 서브에이전트(`/review`)와 `docs/spec/code-conventions.md` 5-1이 잡는다.
