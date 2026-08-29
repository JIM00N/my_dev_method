#!/usr/bin/env python3
"""검사 J — 계획 깊이 (self:plan 계획 문서).

    .claude/scripts/check-plan.py [--state <파일>]

계획이 요구사항에서 멈추면 "어떻게 동작하는가"가 전부 구현 시점으로 미뤄지고,
답이 없는 칸은 에이전트가 그 자리에서 지어낸다. 그래서 키트가 만든 계획은
기능 → 사양까지 내려가고, 사양마다 영향 영역·선행·먼저를 갖는다.
정본: docs/guides/plan.md 「4절 사양 표를 채우는 법」·「정본이 두 벌 되지 않는 이유」.

**출처가 self:plan 인 문서만 본다.** 외부 상류의 스냅샷은 읽기 전용이고 형식이 그쪽 것이라,
형식을 강제하면 외부 도구를 쓰는 프로젝트가 첫 검사에서 막힌다 —
그쪽은 docs/spec/source-map.md 4절 계약 확인표가 판정으로 다룬다.

**도입(/mdm-adopt) 전에도 돈다.** 계획을 만든 직후가 깊이를 고칠 수 있는 유일한 시점이고,
그때는 매핑표가 아직 없어 check-consistency.sh 의 A~I 는 쉰다.

**왜 파이썬인가** — 이 검사의 입력은 사람이 자유롭게 쓰는 마크다운이고, 그 입력 공간은
무한 꼬리를 갖는다(CR · 탭 · NBSP · HTML 주석 · 펜스 3종 · escape 파이프 · setext · IFS 접힘).
셸로 파싱하던 판에서 같은 계열의 결함이 표 리더 다섯 개에서 반복해 확정됐다
(table_of · reg_table · data_rows · plan_rows · plan_scan). 회전을 더 돌려 닫히는 종류가
아니라고 판단해 **파서를 파이썬으로 옮겼다** (0.8.0, 사용자 결정 — 갈래 A).
그 대가로 **python3 가 키트 강제 장치의 필수 의존이 된다** — check-consistency.sh 는
python3 가 없으면 J 를 건너뛰지 않고 **실패**한다. 조용히 안 도는 검사는 없는 검사다.

출력: 「실패  …」 · 「경고  …」 · 그 밖의 알림 줄. check-consistency.sh 가 그대로 흘려보낸다.
종료코드: 0 통과 · 1 실패 있음 · 2 경고만 있음. (그 밖의 값은 호출자가 실패로 다룬다)
--state 파일에는 호출자가 꼬리말을 고르는 데 쓰는 상태를 적는다:
    ran=<0|1>        J 가 실제로 돌았는가 (self:plan 대상이 있었는가)
    plan_row=<0|1>   docs/upstream/plan.md 가 수집 기록에 행으로라도 있는가
"""
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
UPSTREAM = os.path.join(ROOT, "docs", "upstream")
MANIFEST = os.path.join(UPSTREAM, "manifest.tsv")

fail = 0
warn = 0


def note(msg):
    print(msg)


def bad(msg):
    global fail
    print("실패  %s" % msg)
    fail = 1


def caution(msg):
    global warn
    print("경고  %s" % msg)
    warn = 1


# ── 읽기 ────────────────────────────────────────────────────────────────
def read_lines(path):
    """줄 목록. 줄끝 CR·LF 를 떼고, 후행 개행이 없는 마지막 줄도 살린다.

    인코딩을 명시한다 — 로케일에 따라 바이트로 읽히면 한글·em dash 안의 바이트가
    문자 클래스에 걸려 검사가 조용히 어긋난다 (이 저장소가 셸에서 두 번 밟은 자리).
    깨진 바이트는 버리지 않고 대치 문자로 남긴다 — 조용히 사라지면 그 줄이 검사에서 빠진다.
    """
    with open(path, encoding="utf-8", errors="replace", newline="") as f:
        text = f.read()
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return [ln[:-1] if ln.endswith("\r") else ln for ln in lines]


def trim(s):
    """앞뒤 공백 제거. 파이썬의 strip 은 NBSP(U+00A0) 같은 유니코드 공백도 다룬다 —
    셸 판이 못 먹던 자리다 (이슈 #264·#272)."""
    return s.strip()


# ── 표 읽기 ──────────────────────────────────────────────────────────────
def split_cells(row):
    """'|' 로 가른다. **마지막 구분자가 만드는 빈 칸 하나만** 버린다 —
    셸의 `IFS='|' read -a` 와 같은 규칙이라 열 번호가 두 구현에서 같다."""
    parts = row.split("|")
    if parts and parts[-1] == "":
        parts.pop()
    return parts


def col_idx(row, want):
    """머리행에서 열 이름의 자리 번호(1부터). 없으면 None.
    열 위치를 고정하지 않는다 — 이름으로 찾으므로 열이 늘어도 깨지지 않는다."""
    for i, f in enumerate(split_cells(row), start=1):
        if trim(f) == want:
            return i
    return None


def cell(row, idx):
    if idx is None:
        return ""
    parts = split_cells(row)
    if idx - 1 >= len(parts):
        return ""
    return trim(parts[idx - 1])


def is_ph(v):
    """칸이 **양식 플레이스홀더**인가 — 통째로 <…> 이고 안에 '>' 가 없을 때만 그렇다.

    이것이 없으면 골격에서 **앵커 칸만 실값으로** 바꾼 계획이 J 를 통째로 빠져나간다 —
    「채워져 있다」가 빈 칸 셋만 보던 자리다 (#342). 반대로 `<script> 태그` 나
    `<대기> → <완료>` 같은 **실값**을 양식으로 오인하면 정상 계획이 붉어진다 (#362·#363).
    """
    return len(v) >= 2 and v.startswith("<") and v.endswith(">") and ">" not in v[:-1]


def pcell(row, idx):
    """칸 값을 읽되 **양식 플레이스홀더는 빈 칸으로 본다.**"""
    v = cell(row, idx)
    return "" if is_ph(v) else v


EMPTY = ("", "—", "-")


# ── 계획 문서 스캔 ───────────────────────────────────────────────────────
# 계획 문서를 한 번 훑어 **소제목과 표 데이터 행을 한 스트림**으로 낸다.
#   ("H", 절, 깊이, 제목, "", "")   … 소제목
#   ("R", 절, 깊이, 제목, 머리행, 데이터행)  … 앵커 열 둘을 **함께** 가진 표의 데이터 행
#
# **앵커 열을 둘 요구한다.** 하나만 보면 계획의 다른 표(낱말 정의·색인)가 걸려 정상 문서가
# 붉어진다 (#293). 절 번호로 찾지 않는다 — 골격의 절 번호가 바뀌어도 안 깨지고,
# 앵커 열을 바꾸면 표를 못 찾아 「한 건도 못 찾았다」로 붉어진다 (fail-closed).
#
# **표 안 빈 줄에서 절단하지 않는다** (#279). 절단이 무음이면 그 아래 행 **전부**가
# 조용히 빠져 「가장 빈 행」이 검사에서 사라진다.
#
# 걸러내는 것: 코드펜스(``` 와 ~~~ 둘 다 — #281) · 4칸 들여쓴 코드블록 · HTML 주석(#358) ·
# 구분줄 · 양식 행(**앵커 칸**이 통째 <…> — #280). 후행 개행 없는 마지막 줄도 읽는다.
def plan_scan(path, a1, a2):
    if not os.path.isfile(path):
        return []
    out = []
    sec = "(문서 머리)"
    title = "(문서 머리)"
    lv = 0
    hdr = ""
    fence = ""
    in_comment = False
    for raw in read_lines(path):
        line = raw.lstrip()
        # 코드펜스 — 연 문자와 같은 문자로만 닫힌다
        if fence:
            if line.startswith("```") and fence == "b":
                fence = ""
            elif line.startswith("~~~") and fence == "t":
                fence = ""
            continue
        if line.startswith("```"):
            fence = "b"
            continue
        if line.startswith("~~~"):
            fence = "t"
            continue
        # HTML 주석은 **렌더되지 않는다** — 펜스·4칸 코드블록과 같은 부류다 (#358).
        # 안 거르면 주석 안 유령 행이 사양·기능·역할 백스톱을 전부 무력화한다.
        # 한 줄 주석과 줄 중간에서 닫히는 주석도 처리한다 — 닫힌 뒤 남은 글자로 이어서 판정한다.
        while True:
            if in_comment:
                if "-->" in line:
                    line = line.split("-->", 1)[1]
                    in_comment = False
                else:
                    line = ""
                    break
            else:
                if "<!--" in line:
                    pre, rest = line.split("<!--", 1)
                    if "-->" in rest:
                        line = pre + rest.split("-->", 1)[1]
                    else:
                        line = pre
                        in_comment = True
                        break
                else:
                    break
        line = line.lstrip()
        if not line:
            continue
        # 앞공백 4칸(또는 탭)부터는 GFM 코드블록이다 — 표·제목은 3칸까지만 렌더된다
        if raw.startswith("    ") or raw.startswith("\t"):
            continue
        if line.startswith("#"):
            n = len(line) - len(line.lstrip("#"))
            rest = line[n:]
            # '#' 7개 이상은 GFM 이 제목으로 렌더하지 않는다. '#' 뒤 공백도 요구한다
            if n <= 6 and (rest == "" or rest.startswith(" ")):
                lv = n
                title = trim(rest).replace("\t", " ")
                if n <= 2:
                    sec = title
                hdr = ""
                out.append(("H", sec, lv, title, "", ""))
                continue
        if not line.startswith("|"):
            hdr = ""            # 산문에서 표가 끝난다 (표 안 빈 줄은 위에서 이미 넘겼다)
            continue
        # escape 파이프는 셀 구분자가 아니다 — 열이 밀리면 빈 칸이 면제되거나
        # 엉뚱한 칸을 읽는다 (#294)
        line = line.replace("\\|", "&#124;")
        # 구분줄(|---|:--:|)만 뺀다. '-' 가 없으면 구분줄일 수 없다 —
        # 전부 빈 칸인 행까지 빼면 검사가 잡으려는 「가장 빈 행」이 유일하게 빠져나간다 (#285).
        # 공백 판정은 유니코드 공백 전부다 — 셸의 리터럴 문자 클래스는 CR·탭·NBSP 를 못 먹어
        # 구분줄 끝에 **보이지 않는 문자 하나**만 붙으면 구분줄이 데이터 행으로 세어졌다 (#357).
        if "-" in line:
            if not [c for c in line if not (c.isspace() or c in ":|-")]:
                continue
        if not hdr or col_idx(line, a1) is not None:
            # 머리행 — 앵커 둘을 함께 가져야 이 표를 본다
            if col_idx(line, a1) is not None and col_idx(line, a2) is not None:
                hdr = line.replace("\t", " ")
            continue
        # 양식 행 판정은 **앵커 칸** 기준이다 — 물리적 1번 칸이 아니다 (#280)
        if is_ph(cell(line, col_idx(hdr, a1))):
            continue
        out.append(("R", sec, lv, title, hdr, line))
    return out


# ── 수집 기록에서 self:plan 문서를 고른다 ────────────────────────────────
# **형식 이탈을 조용히 넘기지 않는다** (#282·#324·#360) — 탭이 공백이 되거나 칸이 비면
# 옛 셸 판은 출처를 잘못 읽어 J 가 통째로 꺼졌고, 그런데도 「J 만 돌았다」를 출력해
# **거짓 통과 주장**이 됐다. 파이썬은 탭으로 정확히 넷으로 가른다 — IFS 접힘이 없다.
def pick_targets():
    targets = []
    plan_row = 0
    if not os.path.isfile(MANIFEST):
        return targets, plan_row
    for mline in read_lines(MANIFEST):
        if mline == "" or mline.startswith("#"):
            continue
        ntab = mline.count("\t")
        if ntab != 3:
            bad("docs/upstream/manifest.tsv — 탭 4열이 아닌 줄이 있다 (탭 %d개 — 4열이면 3개다): "
                "'%s' → 파일<TAB>출처<TAB>수집시각<TAB>sha256 으로 고친다. "
                "형식이 어긋나면 검사 A·J 가 그 줄을 못 보고 조용히 통과한다" % (ntab, mline))
            continue
        jf, jsrc, jat, jsha = [trim(x) for x in mline.split("\t")]
        if not jf or not jsrc or not jat or not jsha:
            bad("docs/upstream/manifest.tsv — 네 칸 중 빈 칸이 있다: '%s' → "
                "파일<TAB>출처<TAB>수집시각<TAB>sha256 을 모두 채운다. "
                "빈 칸을 넘기면 출처를 잘못 읽어 검사 J 가 조용히 꺼진다" % mline)
            continue
        if jf == "plan.md":
            plan_row = 1
        if jsrc != "self:plan":
            continue
        if not os.path.isfile(os.path.join(UPSTREAM, jf)):
            # 검사 A 는 「도입 전」 조기 종료 뒤에 있어 이 창에서는 안 돈다 — J 가 직접 알린다 (#286)
            bad("docs/upstream/%s — 수집 기록에 있는데 파일이 없다 → "
                "/mdm-plan 을 다시 돌리거나 manifest.tsv 의 줄을 지운다" % jf)
            continue
        targets.append(jf)
    return targets, plan_row


# ── J-1. 사양 표 — 계층이 끝까지 내려갔고, 행마다 영향 영역·선행·먼저가 채워졌는가 ──
def check_specs(jf, jp):
    n_spec = 0
    l_hdr = None
    ok_cols = False
    idx = {}
    # 어느 '##' 절이 요구사항 절인가 — **절 제목에 「요구사항」이 들어간 절**이다.
    #
    # 옛 판은 「사양 행이 **발견된** 절」로 잡았고, 그것이 순환이었다 (#320):
    # 사양 표가 아예 없는 절 = 계획이 요구사항에서 멈춘 **바로 그 절** = 전칭 검사가 잡으려는
    # 대상이 구조적으로 사정권 밖이 된다. 절 **번호**는 여전히 못 박지 않는다 —
    # 대신 낱말 하나를 요구하고, 그 요구를 docs/guides/plan.md P3 4절이 명시한다.
    st = {"req": "", "req_feat": 0, "feat": "", "feat_spec": 0,
          "in_sec": False, "sec": "", "sec_req": 0, "n_sec": 0}

    # 요구사항·기능이 닫힐 때 「아래가 비었나」를 판정한다 — 전칭 주장의 구현이다 (#283).
    def close_feat():
        if not st["feat"]:
            return
        if st["feat_spec"] <= 0:
            bad("docs/upstream/%s 「%s」 — 이 기능에 사양 표가 없다. 기능에서 멈추면 "
                "«어떻게 동작하는가»가 구현 시점으로 미뤄져 그 자리에서 지어내진다 → "
                "사양 표를 만든다 (docs/guides/plan.md P3 4절)" % (jf, st["feat"]))
        st["feat"] = ""
        st["feat_spec"] = 0

    def close_req():
        if not st["req"]:
            return
        if st["req_feat"] <= 0:
            bad("docs/upstream/%s 「%s」 — 이 요구사항에 기능(####)이 없다. 요구사항에서 멈춘 것이다 → "
                "요구사항(###) → 기능(####) → 사양(표) 세 층으로 나눈다 "
                "(docs/guides/plan.md P3 4절)" % (jf, st["req"]))
        st["req"] = ""
        st["req_feat"] = 0

    def close_sec():
        if not st["in_sec"]:
            return
        if st["sec_req"] <= 0:
            bad("docs/upstream/%s 「%s」 — 이 요구사항 절에 요구사항(###)이 없다. "
                "절 제목만 세우고 산문으로 끝난 것이다 → 요구사항(###) → 기능(####) → 사양(표) "
                "세 층으로 나눈다 (docs/guides/plan.md P3 4절)" % (jf, st["sec"]))
        st["in_sec"] = False
        st["sec"] = ""
        st["sec_req"] = 0

    for kind, _jsec, jlv, jtitle, jhdr, jrow in plan_scan(jp, "사양", "영향 영역"):
        if kind == "H":
            if jlv <= 2:
                close_feat()
                close_req()
                close_sec()
                if "요구사항" in jtitle:
                    st["in_sec"] = True
                    st["sec"] = jtitle
                    st["sec_req"] = 0
                    st["n_sec"] += 1
            elif st["in_sec"] and jlv == 3:
                close_feat()
                close_req()
                st["req"] = jtitle
                st["req_feat"] = 0
                st["sec_req"] += 1
            elif st["in_sec"]:
                close_feat()
                st["feat"] = jtitle
                st["feat_spec"] = 0
                st["req_feat"] += 1
            continue

        if jhdr != l_hdr:
            l_hdr = jhdr
            ok_cols = True
            for name in ("사양", "영향 영역", "선행", "먼저", "트리거", "동작", "결과"):
                idx[name] = col_idx(jhdr, name)
            for name in ("선행", "먼저", "트리거", "동작", "결과"):
                if idx[name] is None:
                    ok_cols = False
                    bad("docs/upstream/%s 「%s」 — 사양 표에 '%s' 열이 없다 → "
                        "docs/guides/plan.md P3 4절의 열 이름을 그대로 쓴다" % (jf, jtitle, name))
        n_spec += 1
        st["feat_spec"] += 1
        if not st["feat"] and st["in_sec"]:
            bad("docs/upstream/%s 「%s」 — 사양 표가 기능 소제목(####) 아래에 있지 않다. "
                "요구사항 바로 밑에 두면 기능 층이 없는 것이다 → 요구사항(###) → 기능(####) → "
                "사양(표) 세 층으로 나눈다 (docs/guides/plan.md P3 4절)" % (jf, jtitle))
            st["feat"] = "(소제목 없는 표)"
        if not ok_cols:
            continue

        sid = cell(jrow, idx["사양"]) or "(ID 없는 사양 행)"
        if pcell(jrow, idx["영향 영역"]) in EMPTY:
            bad("docs/upstream/%s %s — 영향 영역이 비었다. 손댈 모듈·경계를 모르면 무엇을 병렬로 "
                "돌릴 수 있는지 계산할 수 없다 → 영역을 적는다 (아무것도 안 건드리는 사양은 없으므로 "
                "'—' 는 답이 아니다)" % (jf, sid))
        if not pcell(jrow, idx["선행"]):
            bad("docs/upstream/%s %s — 선행 칸이 비었다. 선행이 없으면 '—' 라고 적는다 — "
                "빈 칸은 '선행 없음' 과 '아직 안 봤다' 를 구분하지 못한다" % (jf, sid))
        fst = pcell(jrow, idx["먼저"])
        if not fst:
            bad("docs/upstream/%s %s — '먼저' 칸이 비었다. 먼저 만들 묶음이면 ✅, 아니면 '—' → "
                "docs/guides/plan.md P3 4절" % (jf, sid))
        if "✅" in fst:
            for name in ("트리거", "동작", "결과"):
                if pcell(jrow, idx[name]) in EMPTY:
                    bad("docs/upstream/%s %s — 먼저 만들 묶음인데 '%s' 가 비었다. 첫 묶음은 계획 "
                        "단계에서 동작까지 정한다 (나머지 묶음은 /mdm-ready 가 그때 채운다) → "
                        "docs/guides/plan.md P3 4절" % (jf, sid, name))

    close_feat()
    close_req()
    close_sec()
    # 요구사항 절을 하나도 못 찾으면 **조용히 건너뛰지 않는다.** 옛 판은 레벨 1–2 ATX 제목이
    # 없으면 전칭 셋이 통째로 무음이었다 (#322). 못 찾은 것 자체가 신호다 — fail-closed.
    if st["n_sec"] <= 0:
        bad("docs/upstream/%s — 요구사항 절을 찾지 못했다. 검사 J 는 제목에 「요구사항」이 든 "
            "'##' 절 안에서 요구사항(###) → 기능(####) → 사양(표) 계층을 센다 → 그 절을 '##' 로 "
            "세우고 제목에 「요구사항」을 넣는다 (setext 제목 ===/--- 은 읽지 않는다. "
            "docs/guides/plan.md P3 4절)" % jf)
    if n_spec <= 0:
        bad("docs/upstream/%s — 사양 행을 한 건도 찾지 못했다. 계획이 요구사항에서 멈췄거나 "
            "사양 표가 양식 그대로다 → 기능(####)과 사양 표를 채운다 (docs/guides/plan.md P3 4절). "
            "추출 0 건을 통과로 세지 않는다" % jf)


# ── J-2. 권한 표 — 누가 무엇을 할 수 있나는 요구사항 그 자체다 (P3 2절) ──
def check_roles(jf, jp):
    n_role = 0
    r_hdr = None
    r_ok = False
    ri_role = None
    ri_deny = None
    for kind, _jsec, _jlv, _jtitle, rhdr, rrow in plan_scan(jp, "역할", "거부되면"):
        if kind != "R":
            continue
        if rhdr != r_hdr:
            r_hdr = rhdr
            r_ok = True
            ri_role = col_idx(rhdr, "역할")
            ri_deny = col_idx(rhdr, "거부되면")
            if col_idx(rhdr, "할 수 있는 것") is None:
                r_ok = False
                bad("docs/upstream/%s — 권한 표에 '할 수 있는 것' 열이 없다 → "
                    "docs/guides/plan.md P3 2절의 열 이름을 그대로 쓴다" % jf)
        n_role += 1
        if not r_ok:
            continue
        if not pcell(rrow, ri_deny):
            bad("docs/upstream/%s 권한 '%s' — '거부되면' 칸이 비었다. 거부 경로가 없는 권한은 "
                "화면마다 다르게 구현된다 → 숨김·안내·오류 중 하나를 적거나, 거부가 없으면 '—'"
                % (jf, cell(rrow, ri_role)))
    if n_role <= 0:
        bad("docs/upstream/%s — 역할 × 권한 표를 찾지 못했다. 누가 무엇을 할 수 있나는 요구사항 "
            "그 자체이고, 늦게 정하면 화면·데이터를 다시 짜게 된다 → 계획 2절에 표를 만든다. "
            "역할이 없는 프로젝트도 그 사실을 한 줄로 적는다 (docs/guides/plan.md P3 2절)" % jf)


def main():
    state_path = None
    argv = sys.argv[1:]
    while argv:
        a = argv.pop(0)
        if a == "--state" and argv:
            state_path = argv.pop(0)
        else:
            sys.stderr.write("쓰는 법: check-plan.py [--state <파일>]\n")
            return 3

    targets, plan_row = pick_targets()
    ran = 1 if targets else 0

    # J 가 쉬는 이유를 **아는 만큼만** 말한다. 옛 판은 무조건 「상류가 외부 도구다」라고 했는데,
    # 그 말은 수집 기록이 없거나 self:plan 행만 빠졌을 때 **거짓**이다 — 배포본 키트가 정확히
    # 그 상태였다 (docs/upstream/plan.md 가 물리적으로 있는데 「self:plan 계획 문서도 없다」고 했다).
    # 키트 양식 자신이 *"외부에서 계획을 받아 온 프로젝트라면 이 파일은 지운다"* 라고 그 상태를 금한다. (#359)
    if not targets:
        has_snapshot = os.path.isdir(UPSTREAM) and any(
            n.endswith(".md") for n in sorted(os.listdir(UPSTREAM)))
        if not os.path.isfile(MANIFEST) and has_snapshot:
            # 검사 A 가 같은 것을 보지만 「도입 전」 조기 종료 뒤라 이 창에서는 안 돈다 (#286 과 같은 처방)
            bad("상류 스냅샷은 있는데 수집 기록이 없다: docs/upstream/manifest.tsv — "
                "/mdm-plan 또는 /mdm-adopt 로 다시 수집한다. 기록이 없으면 검사 J 가 "
                "계획 깊이를 볼 수 없다")
        elif os.path.isfile(os.path.join(UPSTREAM, "plan.md")) and plan_row == 0:
            caution("docs/upstream/plan.md 가 있는데 수집 기록에 self:plan 으로 기록되지 않았다 — "
                    "계획 깊이 검사(J)가 쉰다. /mdm-plan 을 돌려 기록하거나, 상류가 외부 도구라면 "
                    "그 파일을 지운다 (docs/upstream/plan.md 양식 마지막 줄이 그렇게 지시한다).")
        else:
            note("계획 깊이 검사(J)를 건너뛴다 — 출처가 self:plan 인 계획 문서를 "
                 "수집 기록에서 찾지 못했다 (상류가 외부 도구다).")
    else:
        for jf in targets:
            jp = os.path.join(UPSTREAM, jf)
            check_specs(jf, jp)
            check_roles(jf, jp)

    if state_path:
        with open(state_path, "w", encoding="utf-8") as f:
            f.write("ran=%d\nplan_row=%d\n" % (ran, plan_row))

    if fail:
        return 1
    if warn:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
