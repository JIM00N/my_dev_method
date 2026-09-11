---
description: dev-kit 설치·업그레이드 — 제품 저장소에 지시서(CLAUDE.md·AGENTS.md)·문서 골격(docs/)·제품 CI 양식을 심고 플러그인을 프로젝트에 등록한다. 커맨드·훅·검사 엔진은 복사하지 않는다(플러그인이 제공)
argument-hint: [--upgrade [--retire-legacy]]
---

인자: $ARGUMENTS

이 커맨드는 **현재 작업 디렉토리**를 제품 저장소 루트로 본다. 다른 곳이면 먼저 옮긴다 — 잘못된 곳에 `docs/` 를 심으면 지우는 것도 사람이 한다.

1. 실행한다 (엔진 런처 `mdm` 은 플러그인 `bin/` 이 PATH 에 올린다 — 안 잡히면 `${CLAUDE_PLUGIN_ROOT}/bin/mdm`):

   ```bash
   mdm init "$PWD" $ARGUMENTS
   ```

   - 인자 없음 → **신규 설치.** `CLAUDE.md` 나 `docs/` 가 이미 있으면 중단한다.
     **중단되면 스스로 `--upgrade` 로 다시 돌리지 않는다** — 키트를 쓴 적 없는 저장소에서 `--upgrade` 는 그 저장소의
     `docs/index.md`·`docs/MOC.md`·`AGENTS.md` 등을 키트 판으로 교체한다(되돌리려면 git 이력이 필요하다 — issues #229·#428).
     중단 메시지와 이미 있는 파일을 사용자에게 보이고, **키트를 쓰던 저장소라는 답을 받은 뒤에만** `--upgrade` 로 간다.
   - `--upgrade` → 키트 소유 문서(`docs/guides/` 전체 · 카탈로그 index · 양식)만 새 판으로 바꾼다.
     프로젝트가 채운 spec·plan·quality·status·decisions·meta·evidence 는 건드리지 않는다.
     `CLAUDE.md` 는 `CLAUDE.md.dev-kit-new` 로 옆에 두고 사람이 병합한다 (프로젝트명·§6 고유 규칙 보존).
   - `--retire-legacy`(`--upgrade` 와 함께만) → 1.x(복사 방식) 배포본이 제품에 두고 간 `.claude/` 키트 파일 중 **원본과 바이트 단위로 같은 것만**
     `*.dev-kit-1x-retired` 로 물리고, 그 훅의 `settings.json` 등록을 뺀다. 내용이 다른 파일은 어느 경우에도 건드리지 않는다.
     기본(플래그 없음)은 **찾아서 알리기만** 한다.

2. 출력의 **「이어서 할 일」을 사용자에게 그대로 보인다.** 요약하지 않는다 — 각 줄이 사용자의 다음 행동이다.

3. 신규 설치였으면 사용자에게 다음을 확인받는다:
   - `CLAUDE.md` 상단 두 줄(제목·한 줄 설명)을 프로젝트 것으로 바꿨는가
   - `.claude/settings.json` 에 `mdm@my-dev-method` 가 등록됐다 — 세션을 다시 시작해야 훅·커맨드가 잡힌다
   - 그다음 진입점은 하나다: **`/mdm:adopt`** (현재 단계 S0)

4. 업그레이드였으면 사용자에게 다음을 보인다:
   - `git diff` 로 교체된 키트 문서
   - `CLAUDE.md.dev-kit-new` 가 있으면 **새 판으로 교체한 뒤 프로젝트명과 §6 고유 규칙만 되살린다**
   - 원본 저장소 `CHANGELOG.md` 에서 이전 버전 이후의 **「양식 변경」** 항목 — 프로젝트 소유 파일은 사람이 새 양식으로 옮겨 적는다
   - 제품 CI: `.github/workflows/mdm-check.yml` 에 `MDM_KIT_REF` 가 있으면 새 플러그인 버전으로 올린다.
     없으면(1.x 양식) 설치기가 둔 `mdm-check.yml.dev-kit-new` 로 **`--retire-legacy` 전에** 교체한다 — 순서를 뒤집으면 CI 가 옛 엔진 경로를 부르다 깨진다
   - 옛 `.claude/` 키트 파일이 보고됐으면 그 목록과 `--retire-legacy` 의 뜻을 설명하고 **사용자 결정을 받는다** — 대신 정하지 않는다

이 커맨드는 도입(`/mdm:adopt`)을 대신하지 않는다. 설치는 문서 골격을 심는 것이고, 도입은 계획을 앉히는 것이다.
