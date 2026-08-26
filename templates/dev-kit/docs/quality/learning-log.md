# 에러 학습 인제스트 로그

Error Learning Agent가 새 에러 기록을 종합한 결과만 남긴다. 원본 이슈의 재현·수정 내역은 `docs/quality/issues.md`와 `docs/quality/archive/`가 소유한다.

**읽는 시점**: `error-learning` 에이전트가 새 종합 전에 이전 종합과의 중복을 확인할 때, 그리고 Main이 인제스트 결과의 충돌을 검토할 때.
**성장 규칙**: 200줄에 도달하면 오래된 종합부터 `docs/quality/archive/learning-log/`로 옮긴다 (폴더가 없으면 만든다). 실행 주체는 `/cycle-close` 7단계의 인제스트 검토다.

## 기록 양식

```markdown
## YYYY-MM-DD — <유형> 종합
- 원본 이슈: #000
- 공통 원인:
- 영향 Story/사이클:
- 일반화 가능한 규칙 / 규칙 아님:
- 추가·수정한 검수 시나리오:
- 자동 테스트로 승격한 것 / 승격 불가(이유):
- 영향을 받는 문서와 Main 통합 상태:
- 남은 질문:
```

---

(아직 인제스트 기록 없음)
