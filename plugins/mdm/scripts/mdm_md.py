#!/usr/bin/env python3
"""마크다운 표 리더 — 검사 J·K 가 **함께** 쓰는 파서.

왜 모듈인가 — 이 저장소는 같은 결함 계열을 표 리더 **다섯 개**에서 확정했다
(`table_of` #269 · `reg_table` · `data_rows` #267 · `plan_rows` #279 · `plan_scan` #357·#358).
그래서 0.8.0 에서 검사 J 의 파서를 파이썬으로 옮겼고(사용자 결정 — 갈래 A),
검사 K 가 같은 파싱을 필요로 하자 **복제하지 않고 여기로 뽑았다.**
새 검사가 표를 읽어야 하면 리더를 하나 더 만들지 말고 이 파일을 쓴다.

이 파일이 저장소의 유일한 표 리더는 아니다 — A~I 는 아직 셸 리더(`table_of`·`data_rows`·`reg_table`)를,
source-map 은 `mdm_model.py` 를 쓴다. 새 리더를 **더 만들지 않는 것**이 규칙이고(루트 CLAUDE.md),
이 파일은 그 규칙에 따라 J 의 파서를 K 와 나눠 쓰게 뽑은 것이다.
여기 있는 판정은 `scripts/test-consistency.sh` 의 J·K 단언이 덮는다(개수의 정본은 루트 CLAUDE.md).
이 파일을 고치면 그 둘이 함께 붉어져야 한다.
"""
import os


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


# ── 문서 스캔 ───────────────────────────────────────────────────────────
# 문서를 한 번 훑어 **소제목과 표 데이터 행을 한 스트림**으로 낸다.
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
def scan_tables(path, a1, a2):
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
