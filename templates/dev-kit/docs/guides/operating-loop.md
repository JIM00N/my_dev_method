# 변경 한 건의 운영 절차

이 문서는 요구사항 누락 대조·변경 위험·의미 리뷰·인계·동기화·제품 CI의 정본이다.
엔진은 `.claude/scripts/mdm_operations.py`, 실행 진입점은 `.claude/scripts/mdm-ops.py`다.
준비·실행 증거 형식은 `docs/guides/contract-evidence.md`를 함께 따른다.

## 최초 도입: 상류 전체와 처리 목록 대조

상류의 요구사항 선언 형식을 확인한다. 예를 들어 `## FR-1 주문 삭제` 같은 제목이면:

```bash
mkdir -p docs/meta .tmp
python3 .claude/scripts/mdm-ops.py catalog \
  --source docs/upstream/prd.md --pattern '^## (?P<id>FR-[0-9]+)\b' \
  > .tmp/requirements-draft.json
```

파일이 여러 개면 --source를 반복한다. 서로 다른 형식이면 생성한 JSON의 sources에 파일별 pattern을
적는다. **정규식은 실제 요구사항 선언만 선택해야 한다.** 코드 블록·주석은 공통 파서가 제외한다.
추출 0건·중복 ID는 실패한다. 검토 후 초안을 docs/meta/requirements.json으로 옮긴다.
기존 목록을 갱신할 때는 초안을 그대로 덮지 말고 보류·제외·삭제 기록과 병합한다.

requirements의 각 ID에는 disposition, reason, decision이 있다:

| disposition | 뜻 | 검사 |
|---|---|---|
| include | 이번 제품 범위에 반영 | source-map에 취소되지 않은 행이 필요 |
| defer | 후속으로 보류 | 이유·결정 근거 필요. 매핑이 있으면 대기 또는 취소 |
| exclude | 범위 밖 | 이유·결정 근거 필요. 매핑이 있으면 대기 또는 취소 |
| retire | 상류에서 삭제됨 | 이유·결정 근거 필요. 매핑이 있으면 취소. 상류에 재등장하면 실패 |

decision에는 승인 대화·ADR 등 검토 가능한 식별자를 적는다. 빈 이유로 조용히 제외할 수 없다.
`mdm-contract.py adopt`와 운영 check는 상류에서 다시 추출한 전체 ID와 처리 목록·매핑을 대조한다.
삭제된 ID는 retire로 남기고 재사용하지 않는다. ID 재사용의 의미 판정은 변경 리뷰에서 한다.

**추출 설정에 지정하지 않은 문서나 다른 형식의 요구사항은 자동으로 알아내지 못한다.** 최초 도입과
상류 형식 변경 때 원본 전체와 sources/pattern을 대조해야 한다. 이미지·자유 산문은 상류에서 승인한
텍스트 목록으로 먼저 정리한다. 이 절차는 등록한 Story만 대조하던 누락을 줄이며 자연어 완전성 증명은 아니다.

## 변경 위험에 따라 읽을 범위를 선택

register의 --impact를 반복해 영향을 표시한다. 생략은 behavior이며, 기존 Story 정의에도 같은 기본값을 쓴다.

| 영향 | 읽고 비교할 것 | 추가 행동 |
|---|---|---|
| presentation | Story·매핑과 실제 바꿀 화면 | 동작·권한·데이터가 같다는 판단 근거를 슬롯에 남김 |
| behavior | Story와 연결한 계약 | 역할·조건·행동·결과 비교 |
| authorization | 위 항목 + domain·product의 역할과 권한 | 허용·거부 경로 비교 및 테스트 |
| state | 위 항목 + 상태 전이 | 전이 전후·금지 전이 비교 및 테스트 |
| data | 위 항목 + 데이터 규칙 | 불변식·이전 데이터·복구 영향 비교 및 테스트 |
| external | 위 항목 + interfaces·stack | 외부 부작용·실패·재시도 비교 및 테스트 |

```bash
python3 .claude/scripts/mdm-ops.py plan ST-001
```

plan은 이 분류로 읽을 문서 후보와 비교 항목을 출력한다. 파일명은 표준 키트 기준 후보다.
실제 정본이 다른 파일이면 Story의 inputs와 소유권 표를 따라 연결한다.
**기계가 코드 diff에서 위험을 자동 판별하는 것은 아니다.** 불확실하면 behavior 이상으로 분류하고,
구현 중 새 영향이 드러나면 stories.json의 impacts를 넓힌 뒤 다시 준비 판정한다.

프로파일은 제품 전체의 최소 보안·환경 기준을 유지한다. 변경 한 건에서는 영향 없는 설계 문서를
다시 쓰지 않는다. ADR은 되돌리기 어려운 결정이 있을 때, issues는 문제를 발견했을 때,
학습 로그는 새로 종합할 사건이 있을 때만 갱신한다. 변화 없는 문서에 날짜만 찍는 작업은 하지 않는다.
표시 변경도 현재 테스트·정합성·인계 검사는 수행한다. 전역 계약의 파일 해시는 v1의 보수적 범위를 유지한다.

## 의미 리뷰: 정의된 행동을 비교

behavior·authorization·state·data·external 각각에 대해 비교 행을 만든다.
예를 들어 .tmp/comparison.json은 다음 배열이다:

```json
[
  {
    "topic": "authorization",
    "authority": "docs/spec/domain.md#권한",
    "consumer": "docs/plan/stories/ST-001-delete.md#삭제",
    "actor": "작성자 / 다른 사용자",
    "condition": "자신의 주문 / 타인의 주문",
    "action": "삭제 요청",
    "result": "작성자만 삭제 성공, 타인은 거부",
    "resolution": "aligned",
    "reason": "정본과 Story의 허용·거부 경로를 대조함. AC-1/AC-2 테스트와 연결"
  }
]
```

authority·consumer는 파일#실제로 존재하는 본문 조각이다. 원래 문서를 복제하는 대신 비교에 필요한
행동만 기록한다. 충돌을 발견하면 구현 오류는 코드, 승인된 변경의 누락은 정본을 고친다.
미결정 충돌은 사용자에게 판단을 요청한다. 해결한 행은 resolved와 해결 근거를 기록한다.

ready에 --comparison .tmp/comparison.json을 추가한다. 엔진은 영향별 행·실제 인용 위치·판정값을 검사하고
판정 당시 근거와 함께 보존한다. 미해결 판정은 통과하지 않는다. presentation만이면 비교 배열을 생략할 수 있다.
**aligned라고 적은 내용이 논리적으로 옳은지는 사람이 리뷰한다.** 엔진은 자연어 모순 판별기를 가장하지 않는다.

## 세션 인계와 최종 통합

STATUS를 먼저 갱신하고 다음 JSON을 .tmp/handoff.json에 쓴다. 내용의 정본은 이 인계 기록이며
STATUS에는 현재 요약·다음 행동과 기록 위치만 둔다. 다음 세션은 handoff-check 출력도 읽는다.

```json
{
  "done": ["작성자 삭제 구현 및 테스트 통과"],
  "pending": ["모바일 화면 확인"],
  "decisions": ["권한은 작성자만 허용 — ADR 또는 승인 대화 식별자"],
  "next": ["모바일에서 삭제 확인 대화상자를 점검"],
  "blockers": []
}
```

```bash
python3 .claude/scripts/mdm-ops.py handoff --note .tmp/handoff.json
bash .claude/scripts/mdm-check.sh
```

handoff는 현재 파일 집합·내용과 5칸을 연결한다. 증거·리포트·캐시·의존성·빌드 산출물·.tmp·.env는
제외한다. 임시 입력은 .tmp에 둔다. STATUS를 포함해 추적 대상이 바뀌면 다시 인계해야 한다.
오늘 날짜만 적어서는 통과하지 않는다. 이 검사는 문장의 충분함이나 다음 행동의 올바름을 증명하지 않는다.
Stop 훅은 도입 후 이 검사를 쓰며 반복 차단 방지는 유지한다. 최종 통합의 mdm-check.sh에는 그 예외가 없다.
작업 도중에는 check-consistency.sh, 종료·CI에서는 mdm-check.sh를 쓴다.

## 상류 동기화: 검토한 묶음을 반영

수집 어댑터는 새 자료를 .tmp에 저장한다. 원격 조회 실패를 변경 없음으로 보고하지 않는다:

```bash
python3 .claude/scripts/mdm-ops.py freshness --failed '원격 조회 실패 사유'
```

동기화 묶음 예 (.tmp/sync.json):

```json
{
  "schema_version": 1,
  "files": [{"file": "prd.md", "source": "repo:docs/PRD.md", "input": ".tmp/prd-new.md"}],
  "catalog": {
    "schema_version": 1,
    "sources": [{"file": "docs/upstream/prd.md", "pattern": "^## (?P<id>FR-[0-9]+)\\b"}],
    "requirements": {"FR-1": {"disposition": "include", "reason": "", "decision": ""}}
  },
  "mapping": ".tmp/source-map-new.md"
}
```

files는 이번 스냅샷의 Markdown 전체 집합이다. 이전 Markdown 중 빠진 것은 제거 대상으로 표시된다.
index·이미지 파일은 이 엔진이 삭제하지 않는다. mapping은 생략하면 현재 매핑표를 유지한다.
새 요구사항·삭제·소유권 이동을 검토하고, 새 매핑표·처리 목록에도 그 결정을 반영한다.

```bash
python3 .claude/scripts/mdm-ops.py sync-preview --bundle .tmp/sync.json
python3 .claude/scripts/mdm-ops.py sync-apply --bundle .tmp/sync.json --basis '<preview의 basis>'
python3 .claude/scripts/mdm-ops.py freshness
```

preview가 검증한 후보와 현재 파일의 해시가 모두 같을 때만 apply한다. 매핑·목록 구조를 임시 공간에서
먼저 검사한다. 복구 기록을 만든 뒤 스냅샷·manifest·목록·매핑을 교체하며, 중간 예외는 이전 파일로 복원한다.
프로세스 강제 종료로 기록이 남으면 운영 검사도 실패한다. 실행 중인 기록 작업이 없음을 확인한 뒤
남은 docs/meta/.mdm-write.lock 빈 디렉터리를 제거하고 `mdm-ops.py sync-recover`로 복원한다.
복구는 **이전 상태 복원**이다. 새 묶음은 preview부터 다시 반영한다. 전원 손실·파일시스템 손상까지의 보장은 아니다.

freshness는 마지막 시도·마지막 성공 시각·실패/미확인 상태를 구분한다. confirmed_at은 그 시점의
수집 성공 기록이며 **지금 원격이 최신이라는 뜻이 아니다.** 수집자의 출처 주장은 별도 리뷰 대상이다.
반영 후 계약·소유권 의미를 검토하고 ready → verify → render → 최종 검사로 마무리한다.

## 제품 CI와 설치 진단

설치기는 `.github/workflows/mdm-check.yml`을 없을 때만 생성한다. 기존 파일은 보존한다.
이 워크플로는 기록된 실행 증거와 현재 파일, 정합성, 인계를 검사한다. 프로젝트 테스트 러너를
자동으로 추측해 실행하지 않는다. CI에서도 재실행하려면 프로젝트가 승인한 verify 명령을 별도로 연결한다.

```bash
python3 .claude/scripts/mdm-ops.py doctor
python3 .claude/scripts/mdm-ops.py doctor --run
python3 .claude/scripts/mdm-ops.py doctor --github owner/repo --branch main
```

기본 진단은 로컬 설치·도입 표시·CI 파일 존재를 출력한다. 존재는 실제 실행 성공과 다르다.
도입 표시는 설정·목록을 검증한 결과이며 --run은 최종 검사를 실제로 실행해 별도 결과를 출력한다.
선택한 원격 조회는 인증된 gh로 워크플로 활성 상태·해당 브랜치의 필수 검사·HEAD의 성공 관측을 읽는다.
조회하지 않았거나 권한·네트워크 오류면 unknown이다. classic branch protection만 조회하며 rulesets나
다른 브랜치까지 판단하지 않는다. 보호 설정은 자동으로 변경하지 않는다.
조회 필드는 GitHub 공식 [워크플로 API](https://docs.github.com/en/rest/actions/workflows#get-a-workflow),
[필수 검사 API](https://docs.github.com/en/rest/branches/branch-protection#get-status-checks-protection),
[체크 실행 API](https://docs.github.com/en/rest/checks/runs#list-check-runs-for-a-git-reference)를 따른다.

## 파일럿 측정

실제 제품의 요구사항 변경 한 건을 선택하고 상류 변경·세션 교체·종료·업그레이드를 관찰한다.
측정 형식과 실행 가능한 리허설은 원본 방법론 저장소 examples/first-pilot에 있다.
`mdm-ops.py pilot --record .tmp/pilot.json`은 측정값을 검증하고 질문·영향 후보의 유효 비율을 계산한다.
분모가 0이면 null이며 성공률 100%로 보고하지 않는다. actual과 rehearsal은 구분한다.
실전 효과는 구현 전 모순 발견·사후 드리프트·재작업 시간과 문서/질문/오탐 비용을 함께 평가한다.
규칙이나 절차를 줄일 때는 `docs/quality/rules-learned.md`의 통합·폐기 기준을 따른다.
