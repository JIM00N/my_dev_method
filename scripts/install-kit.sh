#!/usr/bin/env bash
# 옛 진입점 — 2.0.0 부터 설치기는 플러그인 안에 있다 (plugins/mdm/scripts/init-project.sh · `mdm init`).
# 이 래퍼는 클론한 원본 저장소에서 옛 명령 그대로 부르는 사람을 위해 남겨 둔다. 인자를 그대로 넘긴다.
exec bash "$(cd "$(dirname "$0")/.." && pwd)/plugins/mdm/scripts/init-project.sh" "$@"
