# STATUS — my_dev_method

**최종 갱신**: 2026-09-12
**프로파일**: Lite
**출시 스탬프**: 2.1.0 (검사 K 신설 — 커밋 승인 2026-09-12. 태그·푸시는 별도 승인 대기)
**기준 커밋**: 81ddce4 (v2.0.1) 위의 작업 트리
**현재 작업**: **정합성 검사 K「품질 명령 확정」 신설 + 2.1.0 릴리스** — 리뷰 통과, 커밋 승인받음

## 검사 K 신설 · 2.1.0 — 2026-09-12

- **왜.** 외부 제안서(「dev-kit 에 하드 계층을 넣는 방법」)를 2.0.1 실물과 대조한 결과, 제안의 진단표는
  0.1.0 이전 스냅샷 기준이라 절반이 틀렸다(훅·검사 A~J·계약 엔진이 이미 하드 계층이다). 그러나 제안이 겨냥한
  **진짜 공백은 실재**했다 — `docs/spec/code-conventions.md` 품질 명령 표는 `S6-build.md` 네 자리와
  `spec/index.md` 두 자리가 완료 판정의 근거로 배선해 두었는데 **읽는 코드가 0건**이었다.
  실물 채택 저장소(callmanager)는 그 표를 채우면서 「CI에서 강제」·「실패 시 조치」 두 열을 지웠고 아무도 몰랐다.
- **사용자 결정 (2026-09-12).** 갈래 **B′ ①만** — 새 문서(gates.md)를 만들지 않고 기존 표를 기계가 읽게 한다.
  gates.md 신설은 반려(게이트 정본이 이미 셋 — §1 · profiles DoD 표식 · contract-evidence). 영업비서 적용은 **하지 않는다**.
- **무엇을 넣었나.** `plugins/mdm/scripts/check-quality.py`(검사 K 본체) · `mdm_md.py`(J·K 공용 표 리더 — `check-plan.py`
  에서 추출, 리더를 복제하지 않는다는 규칙) · `check-consistency.sh` 의 K 호출 블록.
  **착수한 요구사항(🔵·🟡·✅)이 있을 때만** 판정하고 없으면 쉬었다고 말한다 — 갓 설치한 저장소를 붉히지 않는다.
- **리뷰 1회전(6축).** 치명 1·높음 6 제기 → 반증: **확정 1**(#475 첫 표 머리행을 모든 행에 적용 — 순서만 바꾼
  미끼 표로 통째로 우회, 오탐 방향도 재현), 강등 5, 분기 기각 1(python3 분기는 도달 불가한 죽은 코드).
  **회전 판정 실패** → fixture 를 먼저 만들어 RED 를 본 뒤 고쳤다. 재리뷰는 하지 않는다(1회전 규칙). 수정 뒤 남은 치명·높음 없음.
  고친 것: 절 **이름** 앵커 · **행별 머리행 재추출** · 전 행 면제 실패 · 빈 칸 위장 7종·미선택 변형 3종 정규화 ·
  셸 호출 경계 fixture · doctor 진단 목록 · 실패 경로 라우팅 4행 · 가이드/README/런처 표기. 상세는 로컬 issues #473~#509.
- **사용자 요청으로 도장 뒤 3건 추가 처리 (2026-09-12).** #479(신규 설치 STATUS 가 S0 을 가리키게) · #492(착수 건수 계수 fixture —
  🟡·✅ 단독) · #495(배포 양식을 그대로 K 에 물리는 fixture). 넷 다 회귀를 주입한 사본에서 **RED 를 먼저 실측**했다.
  같은 회전의 발견을 고친 것이라 재리뷰는 하지 않는다(1회전 규칙).
- **검증:** CI 9종 로컬 통과 — check-docs · docs-check 47 · review-gate · **consistency 218**(J 112 · K 36 · 뮤테이션 12) ·
  unittest 41 · report 5 · install-upgrade 53 · hooks 15 · launcher 16.
- **2.1.0 릴리스 (사용자 결정 2026-09-12 — #477).** 버전 여섯 자리를 올렸고(검사 12 가 대조) CHANGELOG 에 **업그레이드 영향**을 적었다:
  착수한 기존 제품은 `/plugin update` 직후 품질 명령 표 미기입으로 붉어진다 · 제품 CI 핀을 `v2.1.0` 으로 올린다.
  **남은 것: `v2.1.0` 태그와 푸시 — 커밋 뒤 별도 승인을 받는다** (`commit-policy.md` 「어느 쪽이든 반드시 묻는 것」).
- **남은 것:** 선재 #508(adopt 탐색 규칙이 키트 자신의 빈 양식을 제외 안 함) · 관측 #509(12병렬에서 검사 I fixture 간헐 실패 —
  직렬 36회 재현 실패, CI 는 직렬) · 사유와 함께 미룬 #490·#491·#496·#497·#501~#507.

## 2.0.1 설치 안내 정정 — 2026-09-11

- **사실 확인(공식 문서 discover-plugins · cli-reference · plugins-reference):** Claude Code 는 모든 플러그인 설치를 마켓플레이스 목록(`marketplace.json`)을 거쳐 한다.
  GitHub 주소에서 바로 설치하는 경로는 없다(`--plugin-url` 은 zip 을 그 세션에만 올린다). `/plugin marketplace add owner/repo` 는 Claude Code 가
  저장소를 직접 받는다 — **지금 구조로 이미 클론 없이 설치된다.** 선택지 1(구조 유지 · 안내 정정)을 사용자가 골랐다.
- **팀원 설치 — 실측하지 않은 전제.** Claude Code 2.1.195 는 「프로젝트 settings 만으로 켠 외부 플러그인은 각자 설치 동의」로 바뀌었다(Claude Code CHANGELOG).
  공식 문서는 「외부」를 상대 경로 아닌 출처로 쓰는 곳이 있어(plugin-marketplaces 「Use external sources」) 이 플러그인(`./plugins/mdm`)이 그 대상인지
  문서로 확정되지 않는다. 격리 설정의 `claude -p` 는 폴더 신뢰로 치지 않아(문서) 재현하지 못했다. 그래서 2.0.0 의 약속도, 처음 고친
  「각자 반드시 설치」도 단정하지 않고 「설치되지 않았다고 나오면 한 줄」로 조건부로 적었다(#464). **대화형 세션에서 새 저장소를 열어 확인할 것.**
- **리뷰 1회전(6축):** 높음 1 제기 → 반증 강등(보통), 확정 치명·높음 0 → 판정 **통과**. 고친 것: 설치 한 줄을 마켓플레이스 추가 먼저로(설치만 주면 rc=1) ·
  업그레이드 출력·1.x 절에 팀원 안내 · `init.md` · 하위 디렉토리 서술 조건부 · 단언 강화(한 줄 전체 일치 · 줄바꿈 분할 · 업그레이드 출력) + 뮤테이션 자기검증 ·
  서술을 단언 범위로 좁힘. 상세는 로컬 issues #460~#472.
- **검증:** CI 9종 로컬 통과 — check-docs · review-gate · consistency 179 · unittest · report 5 · docs-check 47 · install-upgrade 52 · hooks 15 · launcher 16.
  새 단언 3건(신규·업그레이드·뮤테이션 지점)은 설치기 수정 전 RED 를 확인했다. 워크플로 아티팩트 Version 12.
- **사용자 결정 (2026-09-11):** 커밋 · 2.0.1 로 올림(#463 — 기존 설치본이 `/plugin update` 로 새 설치기 출력을 받게) · `v2.0.1` 태그 · 푸시.
  버전 여섯 자리(plugin.json · marketplace 항목·metadata · 템플릿 CLAUDE.md 스탬프 · 제품 CI 핀 · AGENTS.md·플러그인 README `--branch`)는 검사 12 가 대조한다.
- **남은 확인:** 팀원 경로 실측(#464) — 대화형 세션에서 `/mdm:init` 한 저장소를 다른 설정으로 열어 폴더를 신뢰했을 때 mdm 이 켜지는지, 「설치되지 않음」이 뜨는지.

## 2.0.0 플러그인 전환 — 2026-09-11

- **구조:** `templates/dev-kit/` → `plugins/mdm/`. 커맨드 `commands/*.md`(`/mdm:adopt` 등, `/mdm:init` 신규), 에이전트 `agents/*.md`
  (`mdm:code-review`·`mdm:error-learning`), `hooks/hooks.json` + 훅 3 + 공용 `hooks/lib-root.sh`, 런처 `bin/mdm`, 엔진 `scripts/`
  (`mdm_env.py`·`init-project.sh`·`legacy-manifest.tsv` 신규), 제품 양식 `templates/`. 루트 `.claude-plugin/marketplace.json`.
- **실측한 전제:** `claude -p --plugin-dir` 로 커맨드 본문 `${CLAUDE_PLUGIN_ROOT}` 치환 · 플러그인 `bin/` 의 Bash PATH 등록 ·
  `hooks.json` 실행을 확인했다. Bash 도구 환경에는 `CLAUDE_PROJECT_DIR` 가 없고, 하위 디렉토리에서 연 세션의 `CLAUDE_PROJECT_DIR` 는 그 하위 경로다.
- **설치기:** `/mdm:init`(`mdm init`)은 문서 골격 + `.claude/settings.json` 플러그인 등록만 심는다. 1.x 잔재는 내용 해시로 분류해 알린다(기본 불간섭).
- **훅:** 표식 `docs/status/STATUS.md` 를 git 최상위까지 위로 찾고, 없으면 판정하지 않는다.
- **제품 CI:** `MDM_KIT_REF` 핀으로 원본을 clone 해 `bin/mdm final`. 핀 없는 1.x CI 옆에는 양식 사이드카를 둔다.
- 워크플로 아티팩트 페이지를 2.0.0 으로 갱신했다(설치 절·`/mdm:` 이름·`mdm check`·1회전).

## 커밋 전 독립 리뷰 — 1회전

- 6축 전부 실행(대규모 변경). K2 는 첫 인스턴스가 10분 무진행으로 실패해 좁혀 재실행했다.
  사용자 지시로 진행 중이던 K2·반증 6개를 Opus 로 다시 띄웠다.
- 높음 7건 제기 → 반증: 확정 3(죽은 회귀 테스트 · 런처 fixture 부재 · 1.x CI 안내 단절) · 강등 3 · 선재로 집계 제외 1.
  **회전 판정은 실패**(확정 높음 3) — 셋 다 fixture 를 먼저 만들어 RED 를 본 뒤 고쳤다. 강등·선재 4건도 이번에 고쳤다.
  재리뷰는 하지 않는다(1회전 규칙). 수정 뒤 남은 치명·높음 없음.
- 보통·낮음 34건 기록. 문서·설치기 실패 경로는 고쳤고, 검사 11·12 fixture 공백 등은 사유와 함께 미뤘다. 상세는 로컬 issues #424~#458.

## 검증 (2.0.0 커밋 당시)

- CI 와 같은 9종: check-docs · review-gate · consistency · unittest 41 · report · docs-check 47 · install-upgrade 49 · hooks 15 · launcher 16.
- `claude plugin validate` 통과(플러그인·마켓). 새 fixture 는 전부 수정 전 RED 를 확인했다.
- 측정하지 않은 것: 실제 마켓플레이스 설치 경로(`/plugin marketplace add JIM00N/my_dev_method`) — 커밋·푸시·태그 뒤에야 가능하다.

## 다음 3가지

1. 푸시 뒤 원격 CI(docs-check 9종)가 통과하는지 확인한다. 제품 CI 양식과 `AGENTS.md` 는 `v2.0.0` 태그를 clone 한다.
2. 실제 마켓플레이스 설치로 새 제품 저장소에서 `/mdm:init` → `/mdm:adopt` 를 한 번 밟는다.
3. 미룬 fixture 공백(issues #441·#442·#444·#445·#448)과 기존 관찰(#418~#423)을 후속에서 정리한다.

## 사용자 결정 — 2026-09-11

- **#437** `--retire-legacy` 옵트인 플래그 **유지** — 사용자 승인. 0.7.0 결정(「설치기는 옛 이름을 건드리지 않는다」)은 기본 동작으로 남고,
  원본과 바이트 단위로 같은 파일의 개칭만 사람이 플래그를 줄 때 한다. 내용이 다른 파일은 어느 경우에도 건드리지 않는다.
- 2.0.0 커밋 · `v2.0.0` 태그 · 푸시 승인 — 이 STATUS 가 그 커밋에 들어간다.

## 한계와 후속

- 플러그인 로드·PATH·훅 실행은 개발 중과 리뷰 중 실측이고 CI 가 재현하지 않는다(Claude Code 가 CI 에 없다).
- 프로젝트 범위 등록은 세션 시작 디렉토리의 `.claude/settings.json` 에서만 읽힌다 — 제품 루트에서 세션을 연다.
- 훅 표식 게이트는 표식을 지우면 꺼진다 — 1.x 에서 훅 파일을 지우면 꺼지던 것과 같은 신뢰 수준.
- 이전 항목: 슬롯 근거의 의미·승인의 진실성·JUnit 생산자의 신뢰성은 해시가 증명하지 않는다. 원격 doctor 는 classic branch protection 만.

## 과거 기록

2026-09-09 V1.0.0 릴리스·2026-09-08 개선 설계·5088617 기준 구현은 `docs/history/STATUS-2026-09-09.md` 에 보존했다.
2026-08-29 까지는 `docs/history/STATUS-2026-08-29.md`. 이슈 상세는 로컬 issues.md, 공개 변경은 `CHANGELOG.md`.
