#!/usr/bin/env python3
"""엔진 위치와 제품 루트 — 플러그인 안에서 돌기 때문에 자기 경로로는 제품을 못 찾는다.

2.0.0(플러그인 전환) 전에는 스크립트가 제품의 `.claude/scripts/` 에 복사돼 있어
`Path(__file__).parents[2]` 가 곧 제품 루트였다. 이제 엔진은 플러그인 캐시(또는 원본 저장소)에 있고
제품은 따로 있으므로, 제품 루트는 **호출 환경**에서 받는다. 우선순위:

    1. MDM_PROJECT_ROOT   — 명시 (CI·fixture·비-Claude 에이전트)
    2. CLAUDE_PROJECT_DIR — Claude Code 가 훅에 준다 (Bash 도구 환경에는 없다 — 실측)
    3. git rev-parse --show-toplevel  — 현재 디렉토리의 저장소 루트
    4. 현재 디렉토리

셸 스크립트(check-consistency.sh·mdm-check.sh)도 같은 순서를 쓴다. 훅은 hooks/lib-root.sh 가 같은 출발점에서
표식(docs/status/STATUS.md)을 git 최상위까지 위로 찾는다 — 하위 디렉토리에서 띄운 세션은 CLAUDE_PROJECT_DIR 가
그 하위 경로이기 때문이다(issues #426) — 갈라지면 셸이 본 제품과
파이썬이 본 제품이 다른 저장소가 된다. 그래서 셸은 자기가 정한 루트를 MDM_PROJECT_ROOT 로 내보낸 뒤
파이썬을 부른다.
"""
import json
import os
import subprocess
from pathlib import Path

ENGINE = Path(__file__).resolve().parent          # plugins/mdm/scripts
PLUGIN = ENGINE.parent                             # plugins/mdm


def project_root():
    for key in ('MDM_PROJECT_ROOT', 'CLAUDE_PROJECT_DIR'):
        value = os.environ.get(key)
        if value:
            return Path(value).resolve()
    try:
        p = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
        if p.returncode == 0 and p.stdout.strip():
            return Path(p.stdout.strip()).resolve()
    except OSError:
        pass
    return Path.cwd().resolve()


def plugin_version():
    """plugin.json 의 version. 없거나 깨졌으면 None — 추측하지 않는다."""
    try:
        with open(PLUGIN / '.claude-plugin' / 'plugin.json', encoding='utf-8') as f:
            value = json.load(f).get('version')
        return value if isinstance(value, str) and value else None
    except (OSError, ValueError):
        return None
