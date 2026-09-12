#!/usr/bin/env python3
"""검사 K — 품질 명령 확정 (docs/spec/code-conventions.md 「실행 가능한 품질 명령」 표).

    mdm check   (check-consistency.sh 가 이 파일을 부른다)   ·  직접: python3 <플러그인>/scripts/check-quality.py --active <건수>

**왜 이 검사가 있나.** `code-conventions.md` 의 품질 명령 표는 이 프로젝트에서 포맷·린트·타입·테스트를
무엇으로 검사하는지 정하는 자리이고, 같은 문서가 「`완료`는 위에서 이 프로젝트에 해당하는 검사가
통과했다는 뜻이다」라고 못박는다. `docs/guides/S6-build.md` 는 네 자리(구축 전 확인 · 한 덩어리 끝 ·
배포 전 · DoD)에서 이 표를 완료 판정의 근거로 배선한다. 그런데 **그 표를 읽는 코드가 없었다** —
표가 통째로 비어도 「완료」가 통과했고, 실제 채택 저장소에서는 「CI에서 강제」·「실패 시 조치」 두 열이
지워진 채 명령 목록만 남았다 (루트 CLAUDE.md 절대 규칙 3 「구현 없는 약속」).

**어느 표를 보나 — 절 번호가 아니라 절 이름으로 찾는다.**
`SECT_KEY`(「품질 명령」)가 든 제목 아래에서, 앵커 열 `검사`·`명령`을 함께 가진 표만 본다.
절 **번호**로 찾지 않는 것은 골격의 번호가 바뀌어도 안 깨지게 하려는 것이고(`mdm_md.scan_tables` 머리말),
절 **이름**으로 좁히는 것은 문서의 다른 표를 잘못 판정하지 않기 위해서다 — 좁히지 않던 판은
① 부록의 무관한 `검사|명령` 표를 「1절」이라며 붉히고(오탐) ② 그 표 하나로 진짜 표의 공백이
면제되는(우회) 두 방향이 **둘 다 재현됐다** (1회전 K2·K3·K4, 반증 확정).

**열 번호는 행마다 그 행의 머리행에서 뽑는다.** 첫 표의 머리행을 모든 행에 쓰던 판은
열 이름을 하나도 바꾸지 않고 **순서만 바꾼 미끼 표**를 위에 두면 통째로 빠져나갔다.
형제 `check-plan.py` 에는 처음부터 있던 가드이고, 그것을 새 파일에 옮겨 오지 않은 것이 결함이었다.

**언제 도는가.** 매핑표에 🔵·🟡·✅ 요구사항이 하나라도 있을 때만 본다 — 호출자가 그 건수를
`--active` 로 넘긴다. 갓 설치한 저장소와 S4 이전은 표가 비어 있는 것이 정상이라
(`code-conventions.md` 「**코드를 쓰기 전에** 채운다」), 그때 붉히면 모든 제품이
`/mdm:init` 직후 실패한다. 착수 전에는 **쉬었다고 말하고** 통과한다 — 조용히 안 도는 검사는
없는 검사다. 같은 이유로 **전 행이 「해당 없음」이면 침묵하지 않고 실패한다** — 확정된 품질 명령이
0 개인 것은 쉬는 것이 아니라 판정할 것이 사라진 것이다 (1회전 K1·K2, 반증이 남긴 한 줄).

**무엇을 잡나.**
  K1 문서 부재            착수했는데 code-conventions.md 가 없다
  K2 표 부재 (fail-closed) 품질 명령 절에서 앵커 표를 못 찾았다 — 절 이름·열 이름을 바꿔 빠져나가는 것을 막는다
  K3 열 부재              「CI에서 강제」 열이 없다 (채택 저장소가 실제로 지운 열이다)
  K4 명령 빈 칸           「해당 없음」으로 답하지 않은 행에 명령이 없다
  K5 미선택 양식          「CI에서 강제」 칸이 `예 / 아니오` 메뉴 그대로다
  K6 전 행 면제           판정 대상 행이 전부 「해당 없음」이다 — 확정된 명령이 0 개다

**빈 칸·미선택을 눈에 보이는 대로 판정한다.** ZWSP·NBSP·`&nbsp;`·`<br>`·빈 코드스팬·대시 6종은
렌더 화면에서 빈 칸과 구별되지 않는다. 그것들을 값으로 받으면 「채웠다」가 위조된다 (1회전 K2 실측).

**무엇을 안 잡나.** 적힌 명령이 실제로 도는지는 보지 않는다 — 그것은 `mdm contract verify` 의
JUnit 실행 증거와 제품 CI 의 몫이고, 이 검사는 **명령이 확정돼 있는가**까지다. 이 한계를
문서에 권고가 아니라 약속으로 적지 않는다.

출력: 「실패  …」 · 그 밖의 알림 줄. check-consistency.sh 가 그대로 흘려보낸다.
종료코드: 0 통과(쉰 경우 포함) · 1 실패 있음.
"""
import os
import re
import sys

import mdm_env
from mdm_md import cell, col_idx, is_ph, scan_tables

# 제품 루트는 호출 환경이 정한다 (mdm_env.py 머리말) — 엔진은 플러그인 안에 있다.
ROOT = str(mdm_env.project_root())
DOC = os.path.join(ROOT, "docs", "spec", "code-conventions.md")
REL = "docs/spec/code-conventions.md"

# 표를 찾는 자리. 절은 **이름**으로, 표는 앵커 **두 열**로 좁힌다.
SECT_KEY = "품질 명령"
A1 = "검사"
A2 = "명령"
CI_COL = "CI에서 강제"

NA = "해당 없음"
# 양식이 주는 선택지 메뉴. 칸이 이 낱말들의 나열 그대로면 **아직 고르지 않은 것**이다 —
# 「예 / 아니오 / 해당 없음」을 답으로 받으면 그 행이 통째로 면제된다.
MENU_WORDS = {"예", "아니오", NA, NA.replace(" ", "")}
# 빈 칸으로 쓰이는 대시들 — em·en·minus·hyphen·figure·horizontal bar.
DASHES = "—–−‐‒―-"
# 보이지 않는 문자. 렌더 화면에서는 빈 칸과 같다.
INVISIBLE = "​‌‍﻿"

fail = 0


def note(msg):
    print(msg)


def bad(msg):
    global fail
    print("실패  %s" % msg)
    fail = 1


def norm(v):
    """칸 값을 **렌더 화면에서 보이는 대로** 고친다.

    `<br>` 는 메뉴 구분자로 본다 — `예<br>아니오` 는 화면에서 `예 / 아니오` 와 같은 미선택 메뉴다.
    보이지 않는 문자·빈 코드스팬·`&nbsp;` 는 지운다. 안 지우면 ZWSP 한 글자로 빈 칸이 위조된다.
    """
    if not v:
        return ""
    v = re.sub(r"<br\s*/?>", "/", v, flags=re.IGNORECASE)
    v = v.replace("&nbsp;", " ").replace(" ", " ")
    v = re.sub(r"`\s*`", "", v)          # 빈 코드스팬
    v = "".join(c for c in v if c not in INVISIBLE)
    return re.sub(r"\s+", " ", v).strip()


def is_menu(v):
    """미선택 양식 칸인가 — 구분자로 갈린 조각이 **둘 이상**이고 전부 메뉴 낱말일 때만 그렇다.

    구분자 하나로 판정하지 않는다: `make lint / make fmt` 같은 실제 답을 양식으로 오인하면
    다 채운 프로젝트가 붉어진다 (검사 J 가 #362·#363 에서 밟은 오탐 계열).
    """
    parts = [p.strip() for p in re.split(r"[/,]", v)]
    parts = [p for p in parts if p]
    return len(parts) >= 2 and all(p in MENU_WORDS for p in parts)


def is_na(v):
    """「해당 없음」으로 답했는가. 앞의 대시 장식은 벗기고, 공백 표기 흔들림은 무시한다
    (`— 해당 없음` · `해당없음` · `해당 없음(CI 미구성)`)."""
    v = v.lstrip(DASHES).strip()
    return re.sub(r"\s+", "", v).startswith(NA.replace(" ", ""))


def is_blank(v):
    # 대시·구분자만 남은 칸도 빈 칸이다 — `<br>` 만 든 칸이 norm 을 거치면 `/` 하나가 된다.
    return v == "" or v.strip(DASHES + "/,").strip() == "" or is_ph(v)


def targets():
    """품질 명령 절 아래의 앵커 표 데이터 행. (머리행, 행, 절 제목) 으로 낸다."""
    out = []
    for kind, sec, _lv, title, hdr, row in scan_tables(DOC, A1, A2):
        if kind != "R":
            continue
        where = title if SECT_KEY in (title or "") else (sec if SECT_KEY in (sec or "") else "")
        if not where:
            continue
        out.append((hdr, row, where))
    return out


def main():
    active = None
    argv = sys.argv[1:]
    while argv:
        if argv[0] == "--active" and len(argv) >= 2:
            active = argv[1]
            argv = argv[2:]
            continue
        print("알 수 없는 인자: %s" % argv[0])
        return 1
    if active is None or not active.isdigit():
        # 호출자가 건수를 안 주면 **판정하지 않고 실패한다.** 기본값으로 넘기면
        # 셸 쪽 오타 하나에 검사가 통째로 꺼진 채 초록이 된다 (런처 `SCRIPTS` 오타 계열 #425).
        bad("품질 명령 검사(K)에 착수 건수(--active)가 오지 않았다 — check-consistency.sh 의 호출을 확인한다")
        return 1

    if int(active) == 0:
        note("품질 명령 검사(K)는 쉬었다 — 진행 중·검수 대기·완료 요구사항이 아직 없다 (%s 의 품질 명령 표는 코드를 쓰기 전에 채운다)" % REL)
        return 0

    if not os.path.isfile(DOC):
        bad("%s 가 없다 — 진행 중·완료 요구사항이 %s건인데 이 프로젝트의 품질 명령이 어디에도 확정돼 있지 않다 "
            "→ docs/guides/S4-architecture.md 2부로 이 문서를 채운다" % (REL, active))
        return 1

    rows = targets()
    if not rows:
        # fail-closed — 절 이름이나 열 이름을 바꾸거나 표를 지우면 「찾지 못했다」로 붉어진다.
        # 추출 0건을 통과로 넘기면 검사가 통과로 위장한다 (루트 CLAUDE.md 셸 함정 3번과 같은 계열).
        bad("%s 에서 「%s」이 든 절 아래의 「%s」·「%s」 열을 함께 가진 표를 한 건도 찾지 못했다 "
            "→ 그 절 제목과 표 머리행을 양식대로 되돌린다 (절 이름·열 이름을 바꾸면 이 검사가 표를 못 찾는다)"
            % (REL, SECT_KEY, A1, A2))
        return 1

    idx_cache = {}
    ci_missing_reported = set()
    judged = 0
    exempt_n = 0
    where_seen = rows[0][2]

    for hdr, row, where in rows:
        if hdr not in idx_cache:
            # **행마다 그 행의 머리행에서 뽑는다.** 첫 표의 열 번호를 다른 표에 쓰면
            # 순서만 바꾼 미끼 표 하나로 진짜 표가 통째로 면제된다 (1회전, 반증 확정).
            idx_cache[hdr] = (col_idx(hdr, A1), col_idx(hdr, A2), col_idx(hdr, CI_COL))
        i_name, i_cmd, i_ci = idx_cache[hdr]

        if i_ci is None and hdr not in ci_missing_reported:
            ci_missing_reported.add(hdr)
            bad("%s 「%s」 절의 품질 명령 표에 「%s」 열이 없다 — 무엇이 CI 에서 막히는지가 사라진다 "
                "→ 머리행에 그 열을 되살린다" % (REL, where, CI_COL))

        name = norm(cell(row, i_name)) or "(이름 없는 행)"
        cmd = norm(cell(row, i_cmd))
        ci = norm(cell(row, i_ci)) if i_ci is not None else ""

        judged += 1
        if is_na(cmd) or is_na(ci):
            exempt_n += 1
            continue
        if is_blank(cmd) or is_menu(cmd):
            bad("%s 「%s」 절 — 「%s」 행에 명령이 없다. 명령이 없으면 이 검사는 「완료」의 근거가 될 수 없다 "
                "→ 실제로 도는 명령을 적거나, 이 프로젝트에 없으면 「%s」이라고 적는다" % (REL, where, name, NA))
        if i_ci is not None and (is_blank(ci) or is_menu(ci)):
            bad("%s 「%s」 절 — 「%s」 행의 「%s」 칸이 아직 선택되지 않았다 (`%s`) "
                "→ 예·아니오 중 하나를 고른다. 고르지 않으면 무엇이 머지를 막는지가 정해지지 않는다"
                % (REL, where, name, CI_COL, ci if ci else "빈 칸"))

    if judged and judged == exempt_n:
        bad("%s 「%s」 절 — 품질 명령 표의 %d 행이 **전부 「%s」**이다. 확정된 검사 명령이 0 개면 "
            "「완료」가 무엇을 통과했다는 뜻인지 정의되지 않는다 → 최소한 하나는 실제로 도는 명령을 적는다"
            % (REL, where_seen, judged, NA))

    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
