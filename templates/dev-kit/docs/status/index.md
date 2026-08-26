# status — 현재 상태 카탈로그·탐색

`STATUS.md`는 **현재만** 담는 세션 연속성 스냅샷이다. 완료·해결·과거 상태를 계속 누적하지 않는다.

## 항상 읽을 파일

- `STATUS.md` — 현재 단계, 프로파일, 병렬 작업, 열린 차단요인, 다음 행동. **200줄 이하 하드 제한.**

## 파일 목록

| 파일 | 역할 |
|---|---|
| `STATUS.md` | 활성 작업·차단요인·다음 행동만 담는 현재 스냅샷 |
| `archive/index.md` | 해결된 차단요인·과거 스냅샷 보관 카탈로그 |

## 어디에 무엇이 있나

```text
현재 활성 작업·차단요인
→ STATUS.md
→ Story(plan/stories/) / cycle(plan/cycles/) 상세 문서

해결된 차단요인      → archive/blockers/
큰 전환 이전의 상태   → archive/snapshots/
완료 Story·Epic      → ../plan/archive/
검증 완료 이슈        → ../quality/archive/
```

## 원칙

- 병렬 작업은 STATUS에서 **한 줄 링크로만** 관리한다. 각 Story·cycle 문서가 상세 상태와 완료 기준의 단일 기준이다.
- 160줄에 도달하면 다음 기록 전에 위 라우팅대로 아카이브한다. 200줄이 하드 제한이다.
- 세션 종료 시 갱신하지 않으면 `.claude/hooks/status-updated.sh`가 종료를 막는다.
