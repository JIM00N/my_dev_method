# .claude — 기계적 강제 계층

`CLAUDE.md`의 규칙은 산문이고, 세션이 길어지면 에이전트는 드리프트한다.
이 폴더는 **드리프트해도 막히는 것**만 담는다. 규칙과 훅이 어긋나면 규칙이 아니라 훅이 실제 동작이다.

## 구성

| 경로 | 무엇 | 대응하는 규칙 |
|---|---|---|
| `settings.json` | 훅 등록 | — |
| `hooks/status-updated.sh` | 작업 트리에 변경이 있는데 STATUS의 "최종 갱신"이 오늘이 아니면 **세션 종료를 막는다** | 절대 규칙 9 |
| `hooks/guard-dependency.sh` | `stack.md`에 없는 패키지 설치를 **막는다** | 절대 규칙 4 |
| `hooks/guard-secrets.sh` | 비밀 파일·비밀값 형태 문자열이 스테이징된 채 `git commit` 하는 것을 **막는다** | 절대 규칙 5 · S4 4부 |
| `agents/error-learning.md` | 에러 종합·인제스트 전용 서브에이전트 (코드는 못 고친다) | `guides/error-learning-ingest.md` |
| `commands/stage.md` | `/stage [n]` — 단계 진입 | `CLAUDE.md` §0 |
| `commands/cycle-close.md` | `/cycle-close` — 사이클 종료 점검 | `S6-build.md` 8절 |
| `commands/ingest-errors.md` | `/ingest-errors` — 학습 인제스트 | `S6-build.md` 6-3 |

## 설치 확인

```bash
chmod +x .claude/hooks/*.sh     # cp -R로 복사했다면 이미 실행 권한이 있다
claude                          # 세션에서 /hooks 로 등록 상태 확인
```

`jq`가 없으면 두 PreToolUse 훅은 **조용히 통과한다**(차단하지 않는다). 강제를 원하면 `jq`를 설치한다.

## 설계 원칙

- **실패 시 통과.** 훅이 판단하지 못하는 상황(도구 없음, git 저장소 아님, 파싱 실패)에서는 항상 통과시킨다. 훅이 작업을 막는 원인이 되면 그날로 꺼진다.
- **비밀값은 출력하지 않는다.** `guard-secrets.sh`는 파일명과 건수만 알린다.
- **오탐이 반복되면 훅을 끄지 말고 좁힌다.** 끄면 규칙이 산문으로 되돌아간다.
- 훅은 규칙 4·5·9만 강제한다. 나머지 규칙(특히 11번 검증 우회 금지)은 리뷰와 `code-conventions.md`가 잡는다.
