# 계약 근거와 실행 증거 — 파일 단위 v1

**이 가이드가 운영 준비·완료 판정의 정본이다.** 적용 엔진은 `.claude/scripts/mdm-contract.py`,
source-map 공통 reader는 `.claude/scripts/mdm_model.py`다. 기존 A~J 중 J·참조·등재 검사는 유지한다.
**내용 해시 + 의존 관계 + 판정 당시 입력**을 연결한다. 별도 해시체인은 만들지 않는다.

## 원칙

1. 계약의 정본은 기존 Markdown과 상류 스냅샷에 둔다. 내용은 복제하지 않는다.
2. Story의 요구사항·의존 파일·수용 기준별 테스트 연결은 docs/meta/stories.json이 소유한다.
3. 준비 판정은 계약 입력의 SHA-256과 12칸 판정 근거를 기록한다. 체크박스만으로 승계하지 않는다.
4. 계약이나 연결이 달라지면 기존 판정은 현재 계약에 유효하지 않다. 검사는 기록을 고치지 않는다.
5. 완료는 현재 계약·코드에서 실행된 수용 기준별 테스트 결과까지 요구한다.
6. 최종 문서 이동·수정 뒤 검사한다. 과거 완료 이력과 현재 근거의 유효성은 구분한다.

**기계가 보장하지 않는 것**: 슬롯 근거의 의미적 타당성, 사람이 실제로 승인했는지, 테스트가
수용 기준을 충분히 검증하는지, 아직 가져오지 않은 원격 상류의 최신성.
`--reviewed-by`는 판정 주체의 기록이지 전자 서명이 아니다. 같은 권한의 에이전트가 JSON·JUnit을
조작하는 공격을 방어하는 장치가 아니다. 의미 검토와 사용자 결정은 기존 절차가 맡는다.

## 저장 위치와 소유권

| 위치 | 역할 | 갱신 |
|---|---|---|
| `docs/spec/source-map.md` | 요구사항·화면·출처·조건 수·작업 상태 | 기존 작성 방식. 준비·테스트 표시는 render가 계산 |
| docs/meta/project.json | 스키마 1, 도입 완료 표시 | adopt가 최초 생성. 설치기·업그레이드는 손대지 않음 |
| docs/meta/stories.json | Story ID → 요구사항·계약 문서·입력 파일·수용 기준별 테스트 | register 또는 검토한 JSON diff |
| `docs/evidence/readiness/` | 과거와 현재의 준비 판정 기록 | ready가 새 번호로 추가 |
| `docs/evidence/verification/` | 테스트 실행 성공·실패 기록 | verify가 새 번호로 추가 |

메타데이터·증거는 제품 저장소가 버전 관리한다. 리포트만 생성물로 제외한다.
설치기는 이 파일들을 미리 채우거나 기존 판정을 새 버전에 자동 승인하지 않는다.
기록 명령은 디렉터리 잠금으로 동시 쓰기를 막는다. 프로세스 강제 종료 후 MDM_BUSY가 계속되면
다른 기록 작업이 없는지 확인하고 docs/meta/.mdm-write.lock 빈 디렉터리를 제거한 뒤 재실행한다.

## 최초 도입과 업그레이드

계획 작성 중에는 명시적으로 초기화 검사를 실행한다:

```bash
.claude/scripts/check-consistency.sh --init
```

**--init은 운영 통과가 아니다.** 계획 깊이와 기존 표 진단을 위한 모드다.
도입 설정이 이미 있으면 이 옵션은 실패한다. 운영 명령에서 설정이 없거나 파싱에 실패하면
도입 전으로 추측하지 않고 실패한다. 설정을 지운 뒤 --init을 호출해도 운영 완료 증거가 되지 않는다.

S0에서 요구사항 매핑·화면 표를 채운 뒤:

먼저 `docs/guides/operating-loop.md`에 따라 상류 전체 처리 목록을 docs/meta/requirements.json에 만든다.
기존 프로젝트의 업그레이드도 필요하다. 이후 명령은 다음과 같다:

```bash
python3 .claude/scripts/mdm-contract.py adopt
```

신규·기존 프로젝트 모두 같은 명령으로 명시적으로 도입한다. 기존 ✅는 준비·실행 증거로 승계하지 않는다.
진행 중·검수 대기·완료인 요구사항은 아래 register → ready → 필요한 verify를 마쳐야 운영 검사가 통과한다.
대기 중인 요구사항은 아직 Story가 없어도 된다. 이미 도입한 저장소의 adopt 재실행은 기록을 보존한다.
잘못된 스키마·ID 중복·필수 열 부재·정의되지 않은 작업 상태는 실패한다.
`취소`는 이 버전에서 별도 수명 필드 이관 전 호환 상태로 허용하며 활성 검사 대상에서 뺀다.

## Story 등록

```bash
python3 .claude/scripts/mdm-contract.py register ST-001 \
  --requirement FR-1 \
  --document docs/plan/stories/ST-001-delete.md \
  --input docs/spec/domain.md \
  --impact authorization \
  --criterion 'FR-1/AC-1=Orders::test_owner_delete' \
  --criterion 'FR-1/AC-2=Orders::test_other_user_denied'
```

위 Story 파일명은 작성 예다. 실제 만든 파일을 지정한다. Lite는 --document에 사이클 문서를 지정한다.
각 수용 기준에 ID를 붙이고, 요구사항ID/기준ID를 키로 연결한다. 같은 기준에 여러 테스트를 연결하려면
--criterion을 반복한다. 한 테스트가 여러 기준을 검증할 수도 있다. 테스트 식별자는 러너가 출력하는
JUnit의 classname::name이며, 함수 이름을 소스에서 검색해 실행 여부를 추측하지 않는다.

등록 전후에 상류의 실제 수용 기준과 연결을 대조한다. 엔진은 알려진 조건 수와 고유 기준 ID 수를
대조하지만 **누락을 감추려고 기준 이름을 새로 지었는지**는 의미 리뷰의 범위다.

같은 Story를 다른 연결로 재등록하면 실패한다. 변경은 stories.json diff로 검토한다.
연결 변경 자체가 입력에 포함되므로, 의존성을 빼거나 테스트 연결을 바꿔도 기존 준비 판정은 낡는다.

## 준비 판정

먼저 입력을 고정해서 읽는다:

```bash
python3 .claude/scripts/mdm-contract.py inspect ST-001
```

출력의 fingerprint와 입력 목록을 근거로 `/mdm-ready`의 초안·크기·사용자 판정을 수행한다.
12칸 결과를 프로젝트의 임시 JSON 파일에 쓴다. 키는 아래 전부를 사용한다:

```
state authorization rules data exceptions presentation checks
preconditions trigger action result acceptance
```

각 값은 아래 형태다:

```json
{"status": "answered", "evidence": "domain.md 권한 표의 작성자 삭제 행 — 사용자 확인"}
```

해당 없으면 status는 not_applicable, evidence에는 이유를 쓴다. 빠진 슬롯·빈 근거·미정 상태는 실패한다.
해당 JSON은 ready가 증거에 복사하므로 임시 원본은 이후 제거할 수 있다.

```bash
python3 .claude/scripts/mdm-contract.py ready ST-001 \
  --basis '<inspect가 출력한 fingerprint>' \
  --assessment '<12칸 판정 JSON의 프로젝트 상대 경로>' \
  --comparison '<영향별 의미 비교 JSON의 프로젝트 상대 경로>' \
  --reviewed-by '<판정 주체와 승인 대화/기록 식별자>'
python3 .claude/scripts/mdm-contract.py render
```

ready는 **검토 시작 때의 해시**를 요구한다. 검토 중 계약이 바뀌면 실패하며 새 입력으로 다시 검토한다.
현재 source-map의 준비 칸에 무엇이 쓰여 있든 운영 판정은 증거에서 계산한다. render는 표시만 갱신하며
과거 해시를 덮거나 실패한 검사를 통과시키지 않는다. 읽기 전용 check와 report도 같은 판정을 계산한다.

## 무엇이 바뀌면 낡는가

준비 입력: Story 정의와 문서 내용, 연결한 요구사항의 ID·출처·화면·조건 수, 명시적 --input 파일,
현재 존재하는 spec 계약 파일 전체(source-map/index 제외), upstream Markdown(index 제외), manifest.
검사 정책 파일(mdm-contract.py·mdm_model.py)의 해시도 포함하므로 엔진 업그레이드는 재판정 대상이다.
운영 정책(mdm_operations.py)과 상류 전체 처리 목록도 입력에 포함한다.
**v1은 보수적으로 파일 전체 바이트를 SHA-256으로 계산한다.** 공백 수정도 재검토를 만든다.
해시가 같다는 것은 내용이 같다는 뜻이며, 의미가 옳다는 뜻이 아니다.

source-map의 준비·테스트·작업 상태·사이클·마일스톤은 계약 해시에서 제외한다. 증거 자체도 입력이 아니다.
Story/사이클의 active → archive 이동은 같은 논리 문서로 찾으므로 내용이 같으면 판정을 유지한다.
다른 계약 파일의 삭제·이름 변경·의존 관계 변경은 다시 확인한다.
문서 내용·완료 체크박스를 고쳤다면 그것도 계약 파일 변경이므로 마지막 내용으로 ready 후 verify한다.

실행 증거는 여기에 코드 파일 집합을 더한다. Git 프로젝트는 추적 파일과 무시되지 않은 새 파일을 읽는다.
비-Git에서는 디렉터리를 순회한다. docs, .claude, .git, 의존성·빌드·캐시·.tmp 디렉터리,
Markdown, .env 계열은 제외한다. 그 밖의 파일은 확장자에 관계없이 내용 해시를 포함한다.
빌드 산출물은 .gitignore 또는 위 제외 디렉터리에 둔다. 환경 변수 값은 기록하지 않는다.
**v1은 런타임·OS·외부 서비스·환경 변화까지 검증하지 않는다.** 환경이 바뀌면 verify를 다시 실행한다.

## 실행 검증

verify가 만드는 빈 임시 JUnit 경로를 환경 변수 MDM_JUNIT_OUTPUT으로 러너에 전달한다.
예를 들어 이미 pytest를 쓰는 프로젝트라면:

```bash
python3 .claude/scripts/mdm-contract.py verify ST-001 -- \
  sh -c 'python3 -m pytest tests --junitxml="$MDM_JUNIT_OUTPUT"'
```

키트가 pytest를 설치하지는 않는다. 프로젝트의 승인된 테스트 러너로 JUnit을 출력한다.
명령을 셸로 감쌀 때 문자열에 외부 입력을 삽입하지 않는다.

새 보고서가 없거나 명령이 실패하면 실패한다. 중복/빈 테스트 식별자, failure/error/skip,
수용 기준에 연결된 테스트 미실행도 실패한다. 입력은 실행 전후에 대조하며 중간 변경이면 실패한다.
**실패한 실행도 새 기록으로 남아 이전 성공을 대체한다.** 성공한 경우에만 현재 완료 근거가 된다.
수동 검증 결과를 자동 테스트 통과로 바꾸어 기록하지 않는다. v1 완료 게이트는 자동 JUnit 근거가 필요하며,
자동화할 수 없는 수용 기준은 완료로 올리지 말고 검수 대기로 두어 사용자와 처리 범위를 결정한다.

## 변경과 종료

`--sync`는 스냅샷·manifest를 갱신하고 영향과 제품 판단을 보고한다. 준비 해시는 갱신하지 않는다.
계약 변경 후 `/mdm-ready`와 필요한 verify를 다시 수행한다. 해시는 원격 상류를 조회하지 않는다.

구현과 계약이 다르면 먼저 원인을 판정한다. 구현 오류는 코드를 수정한다. 승인된 변경의 문서 누락은
정본을 수정한다. 미결정 요구사항은 사용자에게 판단을 요청한다. 구현에 맞추려고 스펙을 낮추지 않는다.

```bash
python3 .claude/scripts/mdm-contract.py render
.claude/scripts/check-consistency.sh
```

**작업 중 전체 정합성은 위 명령, 종료·통합은 인계 후 mdm-check.sh를 사용한다** (`docs/guides/operating-loop.md`).
--scope ST-001은 그 Story가 연결한 요구사항의 증거 검사만
선택한다. 구조 검사와 기존 A~J는 전체에 적용되며, 같은 요구사항을 나눈 Story는 함께 준비되어야 한다.
부분 검사 통과를 프로젝트 전체 완료로 보고하지 않는다.

## 증거와 한계

회귀는 원본 저장소 scripts/tests/test_contracts.py에서 임시 제품 저장소로 실행한다.
설치·도입·준비·계약 변경·과거 근거 보존·재판정·JUnit 실행·실행 중 변경·archive를 검증한다.
단계 1은 파일 단위다. 항목 단위 해시·완전한 코드 영향 그래프·원격 최신성 수집·환경 재현·서명은
아직 구현하지 않았다. 의존 관계의 의미적 완전성은 AI 리뷰와 사용자 판정이 보완한다.
