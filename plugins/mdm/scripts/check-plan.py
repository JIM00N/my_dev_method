#!/usr/bin/env python3
"""검사 J — 계획 깊이 (self:plan 계획 문서).

    mdm check   (check-consistency.sh 가 이 파일을 부른다)   ·  직접: python3 <플러그인>/scripts/check-plan.py [--state <파일>]

계획이 요구사항에서 멈추면 "어떻게 동작하는가"가 전부 구현 시점으로 미뤄지고,
답이 없는 칸은 에이전트가 그 자리에서 지어낸다. 그래서 키트가 만든 계획은
기능 → 사양까지 내려가고, 사양마다 영향 영역·선행·먼저를 갖는다.
정본: docs/guides/plan.md 「4절 사양 표를 채우는 법」·「정본이 두 벌 되지 않는 이유」.

**출처가 self:plan 인 문서만 본다.** 외부 상류의 스냅샷은 읽기 전용이고 형식이 그쪽 것이라,
형식을 강제하면 외부 도구를 쓰는 프로젝트가 첫 검사에서 막힌다 —
그쪽은 docs/spec/source-map.md 4절 계약 확인표가 판정으로 다룬다.

**도입(/mdm:adopt) 전에도 돈다.** 계획을 만든 직후가 깊이를 고칠 수 있는 유일한 시점이고,
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

import mdm_env
from mdm_md import EMPTY, cell, col_idx, pcell, read_lines, scan_tables, trim

# 제품 루트는 호출 환경이 정한다 (mdm_env.py 머리말) — 엔진은 플러그인 안에 있다.
ROOT = str(mdm_env.project_root())
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


# ── 표 읽기 — 공용 모듈 mdm_md.py ────────────────────────────────────────
# 리더는 저장소에 **하나만** 둔다. 같은 결함 계열이 표 리더 다섯 개에서 확정된 뒤
# (table_of · reg_table · data_rows · plan_rows · plan_scan) 파서를 파이썬으로 옮겼고,
# 검사 K 가 같은 파싱을 필요로 하자 복제 대신 mdm_md.py 로 뽑았다.
# `plan_scan` 은 거기서 `scan_tables` 라는 이름으로 산다 — 계획 전용이 아니게 됐다.


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
                "/mdm:plan 을 다시 돌리거나 manifest.tsv 의 줄을 지운다" % jf)
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

    for kind, _jsec, jlv, jtitle, jhdr, jrow in scan_tables(jp, "사양", "영향 영역"):
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
                        "단계에서 동작까지 정한다 (나머지 묶음은 /mdm:ready 가 그때 채운다) → "
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
    for kind, _jsec, _jlv, _jtitle, rhdr, rrow in scan_tables(jp, "역할", "거부되면"):
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
                "/mdm:plan 또는 /mdm:adopt 로 다시 수집한다. 기록이 없으면 검사 J 가 "
                "계획 깊이를 볼 수 없다")
        elif os.path.isfile(os.path.join(UPSTREAM, "plan.md")) and plan_row == 0:
            caution("docs/upstream/plan.md 가 있는데 수집 기록에 self:plan 으로 기록되지 않았다 — "
                    "계획 깊이 검사(J)가 쉰다. /mdm:plan 을 돌려 기록하거나, 상류가 외부 도구라면 "
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
