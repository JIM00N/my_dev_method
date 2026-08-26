# my_dev_method — AI 협업 개발방법론

AI 에이전트와 함께 소프트웨어를 개발할 때, **빠른 첫 구현보다 올바른 결정·권한·검증 증거·재사용 가능한 학습**을 남기기 위한 방법론입니다.

제품 저장소에 복사해 넣는 파일 한 벌(`templates/dev-kit`)로 배포되며, 규칙은 산문이 아니라 **훅과 서브에이전트로 강제**됩니다.

이 저장소에는 제품 코드가 없습니다. 제품별 PRD, 코드, 비밀값, 실행 로그는 각 제품의 로컬 저장소가 소유합니다.

---

## 무엇을 해결하나

AI는 빠르게 만들지만 세 가지를 반복합니다. 각각에 대응하는 장치가 있습니다.

| 문제 | 이 키트의 장치 | 강제 방식 |
|---|---|---|
| 막히면 **검증을 약화시켜 초록불을 만든다** — 테스트 삭제, 단언 완화, 타입 무시, 예외 삼킴 | 절대 규칙 11 + 금지된 우회 표 + `/review` | **서브에이전트** (구현과 분리된 컨텍스트) |
| 세션이 끊기면 **맥락을 잃는다** | `docs/status/STATUS.md` 스냅샷 1장 | **훅** (미갱신 시 세션 종료 차단) |
| **같은 실수를 반복한다** | 이슈 기록 → 2회차 규칙 승격 → 다음 사이클에서 걸림 | **서브에이전트** (`/ingest-errors`) |
| 기술을 임의로 고른다 | `docs/spec/stack.md` 사전 확정 | **훅** (설치 명령·매니페스트 편집 차단) |
| 비밀값이 저장소에 들어간다 | 커밋·파일 쓰기 시점 검사 | **훅** |
| 뭘 만들지 모른 채 코딩을 시작한다 | S1~S4 설계 단계 + 단계별 완료 조건(DoD) | 절차 |

**훅은 산문이 아니라 실제로 막습니다.** 규칙과 훅이 어긋나면 규칙이 아니라 훅이 실제 동작입니다.

## 요구사항

| | 무엇 | 없으면 |
|---|---|---|
| 필수 | **Claude Code** | 훅·커맨드·서브에이전트가 동작하지 않습니다. Codex 등 다른 에이전트는 `AGENTS.md`로 같은 규칙을 읽지만 **기계적 강제는 없습니다** |
| 필수 | **git 저장소** | 비밀값·STATUS 훅이 git을 근거로 판단하므로 검사를 건너뜁니다 |
| 권장 | **jq** (`brew install jq`) | guard 훅 2개가 경고만 남기고 통과합니다 (차단하지 않음) |

개발 지식이 깊지 않아도 됩니다. 설계 단계(S1~S4)는 AI가 **사용자를 인터뷰**해서 채우는 구조입니다.

## 설치

### 1. 이 저장소를 클론합니다

```bash
git clone https://github.com/JIM00N/my_dev_method.git
```

### 2. 대상 제품 저장소에 설치합니다

```bash
my_dev_method/scripts/install-kit.sh <제품 저장소 경로>
```

출력 예시 — 무엇이 생겼는지와 이어서 할 일을 알려줍니다:

```text
dev-kit v0.3.0 → /path/to/제품저장소 (install)

  생성: CLAUDE.md
  생성: AGENTS.md
  생성: docs/ 전체
  생성: .claude/ 전체

설치 완료. 이어서 할 일:
  1. CLAUDE.md 상단의 <프로젝트명>, <한 줄 설명> 치환
  2. docs/status/STATUS.md에 시작 시점 기록 → 현재 단계 S1
  ...
```

스크립트는 **덮어쓰기 사고를 막도록** 설계되어 있습니다.

- 대상이 git 저장소가 아니거나, 작업 트리가 더럽거나, `jq`가 없으면 **경고**합니다.
- `CLAUDE.md`나 `docs/`가 이미 있으면 **중단**합니다 (이미 키트를 쓰는 저장소면 `--upgrade`를 쓰라고 안내).
- 기존 `.claude/`가 있으면 **통째로 덮지 않고 파일 단위로 병합**합니다.

### 3. 기존 `.claude/`가 있는 저장소라면

훅·커맨드·서브에이전트는 자동으로 병합되지만, **`settings.json`은 덮어쓰지 않고** 키트 판을 `.claude/settings.json.dev-kit`으로 따로 둡니다. 이 명령으로 병합하세요 (기존 항목과 자체 훅을 보존하면서 키트 훅을 더합니다):

```bash
cd <제품 저장소>/.claude
jq -s '.[0] as $a | .[1] as $b | $a * $b | .hooks = (
  ($a.hooks // {}) as $ah | ($b.hooks // {}) as $bh |
  reduce ((($ah|keys) + ($bh|keys)) | unique)[] as $k
    ({}; .[$k] = (($ah[$k] // []) + ($bh[$k] // []))))' \
  settings.json settings.json.dev-kit > merged.json \
  && mv merged.json settings.json && rm settings.json.dev-kit
```

### 4. 손으로 설치하려면

```bash
cd <제품 저장소>
cp /경로/my_dev_method/templates/dev-kit/CLAUDE.md .
cp /경로/my_dev_method/templates/dev-kit/AGENTS.md .
cp -R /경로/my_dev_method/templates/dev-kit/docs .
cp -R /경로/my_dev_method/templates/dev-kit/.claude .      # 기존 .claude/가 있으면 이 줄은 쓰지 않는다
```

`cp -R`은 동명 파일(특히 `settings.json`)을 말없이 덮어씁니다. 기존 `.claude/`가 있으면 하위 폴더만 복사하고 위 3번의 병합을 하세요. 훅 실행 권한(755)은 커밋되어 있어 `chmod`가 필요 없습니다.

### 5. 설치 후 할 일

1. `CLAUDE.md` 상단의 `<프로젝트명>`, `<한 줄 설명>`을 바꿉니다.
2. `docs/status/STATUS.md`에 시작 시점을 기록하고 현재 단계를 `S1`로 둡니다.
3. Claude Code를 열고 `/hooks`로 훅 3개가 등록됐는지 확인합니다.
4. `/stage 1`로 시작합니다.

## 무엇이 설치되나

```text
CLAUDE.md              라우팅 전용 지시서 (200줄 이하 하드 제한)
AGENTS.md              Codex 등 호환용 진입점
.claude/
  settings.json        훅 등록
  hooks/               guard-secrets · guard-dependency · status-updated
  agents/              code-review · error-learning (구현과 분리된 리뷰·학습 컨텍스트)
  commands/            /stage · /review · /cycle-close · /ingest-errors
docs/                  문서 37개의 골격 (내용은 프로젝트가 채운다)
  guides/              HOW — 단계별 실행 지시서 (키트 소유, 그대로 복사됨)
  spec/                WHAT — 설계 산출물 (product·domain·interface·stack·architecture·code-conventions·ui)
  plan/                WHEN — roadmap · cycles/ · stories/ · archive/
  status/              NOW — STATUS.md 스냅샷 1장 + archive/
  quality/             issues · test-scenarios · rules-learned · learning-log + archive/
  decisions/           ADR
```

## 처음 한 바퀴 — 무엇이 일어나나

`/stage 1`을 치면 AI가 `docs/status/STATUS.md`를 읽고 현재 단계 가이드 하나만 읽은 뒤 인터뷰를 시작합니다.

| 단계 | AI가 하는 일 | **사람이 하는 일** |
|---|---|---|
| S1 문제·범위 | 인터뷰 질문, `spec/product.md` 작성 | 답한다. **"만들지 않을 것"을 정한다** |
| (프로파일 판정) | 난이도 사분면으로 Lite/Standard/Full 판정 | 확인 — 개인 도구면 절차가 자동으로 줄어든다 |
| S2 도메인·상태 | 데이터·상태 전이표 설계 | 업무가 실제로 어떻게 흐르는지 답한다 |
| S3 인터페이스 | 화면·API·CLI 표면 설계 | 뭐가 보여야 하는지 답한다 |
| S4 구조·스택 | 기술 선택지를 장단점과 함께 제시 | **고른다** (모르면 추천안 채택) |
| S5 시각 설계 | 목업 생성 (화면 없으면 스킵) | 눌러 보고 어색한 곳을 지적한다 |
| S6 구축·검수 | TDD 구현 → `/review` → 수정 | **검수 시나리오를 직접 누른다**, 리뷰 반영을 판정한다 |

역할 분담은 하나입니다 — **문서는 에이전트가 쓰고, 사람은 답하고 누르고 판정합니다.** 문서 정합성(정본·경로·양식·아카이브)은 구조와 훅이 지키므로 사람이 신경 쓸 일이 아닙니다.

S1~S4는 설계이므로 추론을 가장 높게 씁니다(Claude Code `ultrathink`). 여기 품질이 전체 결과를 결정합니다. S5~S6에서는 "구현 → 검수 요청 → 피드백 → 수정" 루프로 모드가 바뀝니다.

## 매일 쓰는 법

| 커맨드 | 언제 | 하는 일 |
|---|---|---|
| `/stage [n]` | 세션 시작 · 단계 진입 | STATUS를 읽고 현재 가이드 하나만 읽은 뒤 모드를 맞춘다 |
| `/review` | **구현 한 덩어리가 끝날 때마다** | `code-review` 서브에이전트가 검증 우회·스펙 드리프트·스택 위반을 검토 |
| `/ingest-errors` | 에러 기록이 쌓였을 때 | `error-learning` 서브에이전트가 2회차 문제를 규칙으로 승격 |
| `/cycle-close` | 사이클 종료 | DoD 대조·리뷰·검사 실행·드리프트 대조·학습 인제스트·아카이브를 순서대로 |

세션의 리듬:

```text
세션 시작   /stage        — 어제 어디까지 했는지 설명할 필요가 없다
구현 덩어리  /review       — 검사 명령이 초록이어도 리뷰 전에는 끝난 게 아니다
세션 끝     STATUS 갱신    — 잊으면 훅이 종료를 막으며 갱신할 목록을 알려준다
사이클 끝   /cycle-close  — 11단계 종료 점검
```

리뷰와 에러 학습을 **구현한 에이전트가 직접 하지 않는 것**이 핵심입니다. 구현한 컨텍스트는 자기 우회를 보지 못합니다.

## 훅이 막았을 때

**우회하지 않습니다.** 막힌 데는 이유가 있고, 우회 금지가 이 방법론의 존재 이유입니다.

| 막힌 것 | 왜 | 무엇을 하면 되나 |
|---|---|---|
| 패키지 설치 · 매니페스트 편집 | `docs/spec/stack.md` 결정 표에 없는 기술 | 사용자에게 선택지·근거를 제시해 승인받고, 결정 표에 추가한 뒤 다시 시도 |
| `git commit` · 파일 쓰기 | 비밀값 형태 문자열 또는 비밀 파일 감지 | 값을 환경 변수로 옮기고 `.gitignore` 확인. 이미 푸시됐으면 **키를 폐기·재발급** |
| 세션 종료 | 변경이 있는데 STATUS의 "최종 갱신"이 오늘이 아님 | STATUS의 최종 갱신·지금 하는 일·다음 3가지를 채우고 다시 종료 |

훅은 **판단하지 못하면 통과시키되 침묵하지 않습니다**(도구 없음·git 아님·파싱 실패 시 stderr 경고). 진짜 오탐이면 훅을 끄지 말고 좁히세요 — 끄면 규칙이 산문으로 되돌아갑니다. 한 건짜리 예외는 `docs/spec/code-conventions.md` 5-1의 예외 표에 기록하고 진행합니다.

## 절차량 조절 — 프로파일

개인 도구 하나에 20개 문서와 6단계 DoD를 요구하면 방법론은 **일부만 지켜지는 게 아니라 통째로 버려집니다.** S1의 난이도 사분면이 절차량을 정합니다.

| 사분면 | 프로파일 |
|---|---|
| 나만 쓴다 × 내 컴퓨터에서만 | **Lite** — 설계 문서 축약 |
| 나만 쓴다 × 원격에서도 / 남도 쓴다 × 내 컴퓨터에서만 | **Standard** |
| 남도 쓴다 × 원격에서도 | **Full** — 줄이지 않는다 |

민감정보를 다루면 사분면과 무관하게 Full입니다. 축약은 각 가이드 **DoD의 프로파일 표식**(`(Standard+)`·`(Full)`)으로만 존재합니다.

**Lite에서도 줄이지 않는 것**: 비목표 · 상태 전이표 · `stack.md` · 자동 테스트 · 이슈 기록과 2회차 규칙 승격 · STATUS 갱신 · 검증 우회 금지. Lite는 **설계 문서를 줄이는 것**이지 검증과 학습을 줄이는 것이 아닙니다.

## 업그레이드

배포본의 버전은 `CLAUDE.md` 첫 줄의 `<!-- dev-kit v… -->` 스탬프로 확인합니다.

```bash
my_dev_method/scripts/install-kit.sh <제품 저장소 경로> --upgrade
```

**키트 소유 파일만** 교체되고, 프로젝트가 채운 spec 내용·사이클·이슈·STATUS·ADR은 건드리지 않습니다. `CLAUDE.md`는 프로젝트명과 §6 고유 규칙이 있어 자동 교체하지 않고 `CLAUDE.md.dev-kit-new`로 두므로, diff로 비교해 규칙 부분만 옮기고 지우세요.

`cp -R docs .`를 다시 실행하면 **프로젝트가 쌓아온 증거가 전부 파괴됩니다.** 소유권 구분표는 [templates/dev-kit/README.md](templates/dev-kit/README.md)에 있습니다.

## 문제가 생기면

| 증상 | 원인·조치 |
|---|---|
| 훅이 전혀 동작하지 않는다 | Claude Code에서 `/hooks`로 등록 확인. 기존 `.claude/settings.json`에 병합하지 않았을 가능성이 큽니다 |
| `jq가 없어 …검사를 건너뛴다` 경고 | `brew install jq`. 없으면 guard 훅 2개가 통과만 합니다 |
| 훅이 정상 작업을 막는다 | 오탐이면 `code-conventions.md` 5-1 예외 표에 한 건 기록 후 진행. 반복되면 훅을 끄지 말고 조건을 좁히세요 |
| STATUS 훅이 계속 막는다 | 같은 세션에서 두 번 연속 막지 않습니다. `**최종 갱신**`을 오늘 날짜로 고치면 통과합니다 |
| 절차가 무겁게 느껴진다 | 프로파일을 낮추지 말고 `docs/guides/profiles.md`로 **확인**하세요. 표식 없는 DoD 항목은 모든 프로파일이 봅니다 |

## 이 저장소의 구성

```text
README.md                   설치·사용법 (이 문서)
templates/dev-kit/          제품 저장소에 복사해 쓰는 실행 템플릿 — 배포되는 실물
scripts/install-kit.sh      설치·병합·업그레이드
scripts/check-docs.sh       문서 참조·경로·훅 검사 (CI에서 실행)
guides/                     방법론 해설 (설계 의도·배경)
examples/first-pilot/       첫 적용 회고 양식
CHANGELOG.md                버전별 변경 기록 (공개 정본)
STATUS.md                   이 저장소 자신의 상태
```

이 저장소도 자기 규칙을 지킵니다 — 프로파일 Lite로 STATUS·이슈 기록·CI 검사를 스스로 운영합니다.

## 적용 원칙

- 목적·범위·권한·중요 위험을 바꾸지 않는 질문은 하지 않습니다.
- 새롭고 되돌리기 어려운 결정은 학습 모드로, 이미 배운 기본값은 실행 모드로 진행합니다.
- **초록불을 만들기 위해 검증을 약화시키지 않습니다.** 테스트 삭제·단언 완화·타입 무시·예외 삼킴은 통과가 아닙니다.
- 서비스 페르소나의 권한과 개발 에이전트의 작업 권한을 분리합니다. Story 문서가 그 계약입니다.
- 병렬 구현은 데이터·권한·API·코드 컨벤션·파일 소유권이 확정된 뒤에만 합니다.
- 산문 규칙은 드리프트하므로, 지킬 수 있는 것은 **훅으로 강제**하고, 훅이 못 잡는 것은 **별도 서브에이전트 컨텍스트**가 잡습니다.
- 제품 코드·테스트·서비스 실행은 제품의 **로컬 개발 환경**에서만 합니다.

## 더 읽을 것

- [guides/getting-started.md](guides/getting-started.md) — 이 방법론이 왜 이렇게 설계됐는지
- [templates/dev-kit/README.md](templates/dev-kit/README.md) — 키트의 파일 소유권·강제 장치 목록
- [CHANGELOG.md](CHANGELOG.md) — 버전별 변경과 그 이유
- [examples/first-pilot/README.md](examples/first-pilot/README.md) — 첫 적용 후 회고 양식

## 라이선스

[MIT](LICENSE). 복사해서 쓰고, 고쳐 쓰고, 자기 프로젝트에 넣어도 됩니다.
`templates/dev-kit/`은 복사해 쓰라고 만든 것이므로 별도 표기 의무를 두지 않았습니다.
