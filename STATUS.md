# STATUS — my_dev_method 저장소 상태

> 이 파일은 방법론 저장소 **자신의** 상태다. 키트가 제품 저장소에 요구하는 것의 최소형(Lite)을 스스로 지킨다.
> 제품 프로젝트의 STATUS는 각 제품 저장소의 `docs/status/STATUS.md`가 소유한다.

**최종 갱신**: 2026-08-26
**프로파일**: Lite (문서 저장소 — 나만 쓰고, 로컬에서만)
**현재 버전**: 0.3.0 (release/0.3.0 브랜치, 태그는 main 머지 후)

## 지금 하고 있는 일

0.2.0 저장소 진단(42건)의 수정 — 훅 보강, code-review 서브에이전트, 프로파일-DoD 통합, 정본 지정, 참조 검증.
추가로 훅 실측 검증에서 발견된 4건(#009~#012: add&&commit 구멍·MultiEdit 미파싱·pip -r 오탐·애드온 안내 불일치)을 수정·재검증했다.

## 다음 3가지

1. LICENSE 선택·추가 (#007 — 공개 배포의 전제)
2. release/0.3.0을 main에 머지하고 v0.3.0 태그
3. 실제 제품 저장소 1곳에 0.3.0을 적용해 첫 파일럿 회고를 `examples/first-pilot/`에 기록

## 열린 이슈

`issues.md`(로컬 전용, 형상 관리 제외) 참조 — 진단의 E 영역(결여 영역) 중 0.3.0에서 다루지 않은 것이 백로그로 남아 있다.
공개되는 버전별 변경 기록은 `CHANGELOG.md`가 정본이다.

## 자동 검증

- `scripts/check-docs.sh` — 문서 참조·경로 검사 (CI: `.github/workflows/docs-check.yml`)
- `scripts/install-kit.sh` — 설치·병합·업그레이드 (신규/기존 `.claude/` 병합/`--upgrade` 3경로 수동 검증됨)
