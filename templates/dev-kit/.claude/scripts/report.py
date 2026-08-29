#!/usr/bin/env python3
"""문서를 사람이 보기 쉬운 HTML 한 장으로 만든다.

    .claude/scripts/report.py <종류> [--open]
    종류: adopt | plan | ready | cycle

**HTML 은 정본이 아니다.** 정본은 언제나 docs/ 아래의 md 다.
이 스크립트는 md 를 읽어 매번 다시 그린다 — 생성물을 손으로 고치지 않는다.
고칠 것이 있으면 md 를 고치고 다시 돌린다.

산출: docs/reports/<종류>-<날짜>.html  (형상 관리에서 제외한다)

정합성을 *강제*하는 것은 check-consistency.sh 이고, 이 파일은 *보여주기*만 한다.

**한때 여기에 «그래서 python3 가 없어도 키트의 강제 장치는 그대로 돈다» 고 적혀 있었다.
0.8.0 에서 철회했다** — 정합성 검사 J 의 본체가 check-plan.py(파이썬)로 옮겨져,
python3 는 이제 키트 강제 장치의 **필수 의존**이다. check-consistency.sh 는 python3 가 없으면
J 를 건너뛰지 않고 실패시킨다. 키트 README 「필요한 것」이 정본이다.
"""
import html
import os
import re
import subprocess
import sys
from datetime import date

KINDS = ("adopt", "plan", "ready", "cycle")
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def rd(*parts):
    p = os.path.join(ROOT, *parts)
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


# ── 마크다운 → HTML (필요한 만큼만) ────────────────────────────────────────
def inline(s):
    s = html.escape(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    return s


def md(text):
    """가벼운 변환기. 표·제목·목록·인용·코드블록만 다룬다."""
    out, lines, i = [], text.split("\n"), 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("```"):
            body = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                body.append(html.escape(lines[i]))
                i += 1
            out.append("<pre><code>%s</code></pre>" % "\n".join(body))
            i += 1
            continue
        if re.match(r"^\|.*\|\s*$", ln) and i + 1 < len(lines) and re.match(r"^\|[\s:|-]+\|\s*$", lines[i + 1]):
            hdr = [c.strip() for c in ln.strip().strip("|").split("|")]
            i += 2
            rows = []
            while i < len(lines) and re.match(r"^\|.*\|\s*$", lines[i]):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            out.append(table(hdr, rows))
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", ln)
        if m:
            lv = len(m.group(1))
            out.append("<h%d>%s</h%d>" % (lv, inline(m.group(2)), lv))
            i += 1
            continue
        if re.match(r"^\s*[-*]\s+", ln):
            items = []
            while i < len(lines) and re.match(r"^\s*[-*]\s+", lines[i]):
                items.append("<li>%s</li>" % inline(re.sub(r"^\s*[-*]\s+", "", lines[i])))
                i += 1
            out.append("<ul>%s</ul>" % "".join(items))
            continue
        if ln.startswith(">"):
            body = []
            while i < len(lines) and lines[i].startswith(">"):
                body.append(inline(lines[i].lstrip("> ").rstrip()))
                i += 1
            out.append("<blockquote>%s</blockquote>" % "<br>".join(body))
            continue
        if re.match(r"^---+\s*$", ln):
            out.append("<hr>")
            i += 1
            continue
        if ln.strip():
            para = []
            while i < len(lines) and lines[i].strip() and not re.match(r"^(\||#{1,6}\s|\s*[-*]\s|>|```|---+\s*$)", lines[i]):
                para.append(inline(lines[i]))
                i += 1
            if para:
                out.append("<p>%s</p>" % "<br>".join(para))
                continue
        i += 1
    return "\n".join(out)


def table(hdr, rows, cls=""):
    th = "".join("<th>%s</th>" % inline(c) for c in hdr)
    tb = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in r) for r in rows)
    return '<div class="tw"><table class="%s"><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>' % (cls, th, tb)


# ── source-map 표 읽기 ────────────────────────────────────────────────────
def section_table(text, num):
    """'## <num>.' 아래 첫 표를 (머리행, 데이터행들)로 돌려준다. 양식 행(<…>)은 뺀다."""
    m = re.search(r"^## %d\..*$" % num, text, re.M)
    if not m:
        return [], []
    seg = text[m.end():]
    nxt = re.search(r"^## ", seg, re.M)
    if nxt:
        seg = seg[:nxt.start()]
    lines = seg.split("\n")
    for i, ln in enumerate(lines):
        if re.match(r"^\|\s*ID\s*\|", ln):
            hdr = [c.strip() for c in ln.strip().strip("|").split("|")]
            rows = []
            for ln2 in lines[i + 2:]:
                if not ln2.startswith("|"):
                    break
                if re.match(r"^\|[\s:|-]+\|\s*$", ln2):
                    continue
                if "<" in ln2:
                    continue
                rows.append([c.strip() for c in ln2.strip().strip("|").split("|")])
            return hdr, rows
    return [], []


def col(hdr, name):
    return hdr.index(name) if name in hdr else -1


def cell(row, idx):
    return row[idx].strip() if 0 <= idx < len(row) else ""


def n_items(s):
    return len([x for x in s.split(",") if x.strip() and x.strip() not in ("—", "-")])


def dashboard(hdr, rows):
    """요구사항 현황을 숫자로 요약한다."""
    i_st, i_rd = col(hdr, "상태"), col(hdr, "준비")
    i_cd, i_ts = col(hdr, "조건 수"), col(hdr, "테스트")
    total = len(rows)
    done = sum(1 for r in rows if "✅" in cell(r, i_st))
    prog = sum(1 for r in rows if "🔵" in cell(r, i_st) or "🟡" in cell(r, i_st))
    block = sum(1 for r in rows if "⛔" in cell(r, i_st))
    notready = sum(1 for r in rows if "❌" in cell(r, i_rd))
    unchecked = sum(1 for r in rows if not cell(r, i_rd))
    cond = tests = 0
    for r in rows:
        c = cell(r, i_cd)
        if c.isdigit():
            cond += int(c)
            tests += n_items(cell(r, i_ts))
    cards = [
        ("요구사항", total, ""),
        ("완료", done, "ok" if done else ""),
        ("진행 중", prog, ""),
        ("막힘", block, "bad" if block else ""),
        ("준비 미달", notready, "bad" if notready else "ok"),
        ("점검 전", unchecked, "warn" if unchecked else "ok"),
    ]
    if cond:
        cards.append(("검증 조건 대비 테스트", "%d / %d" % (tests, cond), "ok" if tests >= cond else "bad"))
    return '<div class="cards">%s</div>' % "".join(
        '<div class="card %s"><div class="n">%s</div><div class="l">%s</div></div>' % (c, v, html.escape(l))
        for l, v, c in cards
    )


def check_output():
    sh = os.path.join(ROOT, ".claude", "scripts", "check-consistency.sh")
    if not os.path.exists(sh):
        return None, ""
    try:
        p = subprocess.run(["bash", sh], capture_output=True, text=True, timeout=120, cwd=ROOT)
        txt = (p.stdout or "") + (p.stderr or "")
        # 마지막 요약 줄은 배너 제목이 이미 말하므로 본문에서 뺀다 (같은 말을 두 번 하지 않는다)
        keep = [l for l in txt.strip().split("\n") if l.strip() and not l.startswith("정합성 검사")]
        return p.returncode, "\n".join(keep)
    except Exception as e:  # 검사가 못 돌아도 리포트는 나온다
        return None, "검사를 실행하지 못했다: %s" % e


def pick_sections(text, names, with_heading=True, lv=2):
    """md 에서 지정한 제목의 절만 뽑아 잇는다. 리포트에 문서를 통째로 붙이지 않기 위한 것.
    lv=2 는 '## 제목', lv=3 은 '### 제목' 을 찾는다 (하위 절에서 끊기지 않게 같은 깊이로만 자른다)."""
    h = "#" * lv
    out, seen = [], set()
    for nm in names:
        # 끊는 조건은 **같은 깊이 이상의 모든 헤딩**이다. `^### ` 만 보면 `## ` 를 못 넘어
        # 뒤따르는 절들이 통째로 이 절에 딸려 들어온다 (이슈 #121).
        stop = "|".join("^%s " % ("#" * k) for k in range(1, lv + 1))
        m = re.search(r"^%s\s+%s.*?$(.*?)(?=%s|\Z)" % (h, re.escape(nm), stop), text, re.M | re.S)
        if not m or not m.group(1).strip() or m.start() in seen:
            continue
        seen.add(m.start())  # 같은 절을 이름만 달리해 두 번 넣지 않는다
        out.append(("## %s\n%s" % (nm, m.group(1).rstrip())) if with_heading else m.group(1).rstrip())
    return "\n\n".join(out)


def story_slots():
    """개발 준비 슬롯을 모아 그린다 — Story 문서의 1-1절과 사이클 문서의 축약 슬롯을 **둘 다** 본다.

    둘은 배타가 아니라 공존한다. 어떤 항목이 Story 문서를 갖는지는
    `docs/guides/profiles.md` 「Story 문서」 행이 정하는데, Standard 는 일부만 문서를 갖고
    나머지는 사이클 문서의 축약 슬롯에 남는다. Story 문서를 하나 찾았다고 사이클 쪽을 건너뛰면
    그 모드에서 리포트가 반쪽이 되고, `docs/guides/ready.md` DoD 의 "리포트를 확인했다"가
    보지 못한 슬롯을 확인한 것으로 통과해 버린다.
    """
    out = []
    sdir = os.path.join(ROOT, "docs", "plan", "stories")
    files = sorted(f for f in os.listdir(sdir)
                   if f.endswith(".md") and "template" not in f) if os.path.isdir(sdir) else []
    for f in files:
        txt = rd("docs", "plan", "stories", f)
        m = re.search(r"^## 1-1\..*?$(.*?)(?=^## |\Z)", txt, re.M | re.S)
        if not m:
            continue
        title = (re.search(r"^#\s+(.+)$", txt, re.M) or [None, f])[1]
        out.append("<h3>%s</h3>%s" % (html.escape(title), md(m.group(1))))
    # 사이클 문서의 축약 슬롯 — Story 문서를 만들지 않은 항목이 여기 남는다 (Lite 는 전부가 여기다)
    cdir = os.path.join(ROOT, "docs", "plan", "cycles")
    cfiles = sorted(f for f in os.listdir(cdir)
                    if f.endswith(".md") and "template" not in f) if os.path.isdir(cdir) else []
    for f in cfiles:
        body = pick_sections(rd("docs", "plan", "cycles", f),
                             ["개발 준비 슬롯"], with_heading=False, lv=3)
        if body.strip():
            cur = " · **현재 사이클**" if f == cfiles[-1] else " · 종료(archive 전)"
            out.append("<h3>%s — 축약 슬롯 (Story 문서를 만들지 않은 항목)%s</h3>%s"
                       % (html.escape(f), cur, md(body)))
    return "\n".join(out)


def status_digest():
    """STATUS 는 통째로 붙이지 않는다 — 지금 무엇을 하고 무엇이 막혔는지만 본다."""
    s = rd("docs", "status", "STATUS.md")
    if not s:
        return ""
    head = "\n".join(l for l in s.split("\n")[:24] if re.match(r"^\*\*", l.strip()))
    body = pick_sections(s, ["지금 하고 있는 일", "다음 3가지", "막힌 것 / 사용자 결정 대기", "열린 이슈"])
    return (head + "\n\n" + body).strip()


CSS = """
:root{--bg:#fff;--fg:#1a1a1a;--mut:#6b7280;--line:#e5e7eb;--card:#f9fafb;
--ok:#047857;--okbg:#ecfdf5;--bad:#b91c1c;--badbg:#fef2f2;--warn:#b45309;--warnbg:#fffbeb;--acc:#1d4ed8}
@media(prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#0f1115;--fg:#e5e7eb;--mut:#9ca3af;
--line:#272b33;--card:#161a21;--ok:#34d399;--okbg:#052e23;--bad:#f87171;--badbg:#3b0d0d;
--warn:#fbbf24;--warnbg:#3a2a06;--acc:#93b4ff}}
:root[data-theme=dark]{--bg:#0f1115;--fg:#e5e7eb;--mut:#9ca3af;--line:#272b33;--card:#161a21;
--ok:#34d399;--okbg:#052e23;--bad:#f87171;--badbg:#3b0d0d;--warn:#fbbf24;--warnbg:#3a2a06;--acc:#93b4ff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.7 -apple-system,BlinkMacSystemFont,"Pretendard","Apple SD Gothic Neo","Noto Sans KR",sans-serif}
.wrap{max-width:1100px;margin:0 auto;padding:32px 20px 80px}
header{border-bottom:2px solid var(--line);padding-bottom:16px;margin-bottom:24px}
h1{font-size:26px;margin:0 0 6px}
.sub{color:var(--mut);font-size:13px}
h2{font-size:19px;margin:36px 0 10px;padding-top:14px;border-top:1px solid var(--line)}
h3{font-size:16px;margin:22px 0 8px}
h4,h5,h6{font-size:14px;margin:16px 0 6px}
p{margin:8px 0}
ul{margin:8px 0;padding-left:20px}
code{background:var(--card);border:1px solid var(--line);border-radius:4px;padding:1px 5px;font-size:.88em;
font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
pre{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 14px;overflow-x:auto}
pre code{background:none;border:0;padding:0}
blockquote{margin:12px 0;padding:10px 14px;border-left:3px solid var(--acc);background:var(--card);border-radius:0 6px 6px 0;color:var(--mut)}
hr{border:0;border-top:1px solid var(--line);margin:20px 0}
a{color:var(--acc)}
.tw{overflow-x:auto;margin:12px 0}
table{border-collapse:collapse;width:100%;font-size:13.5px}
th,td{border:1px solid var(--line);padding:7px 10px;text-align:left;vertical-align:top}
th{background:var(--card);font-weight:600;white-space:nowrap}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin:16px 0 8px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px}
.card .n{font-size:26px;font-weight:650;line-height:1.2}
.card .l{color:var(--mut);font-size:12.5px;margin-top:2px}
.card.ok{background:var(--okbg);border-color:var(--ok)}.card.ok .n{color:var(--ok)}
.card.bad{background:var(--badbg);border-color:var(--bad)}.card.bad .n{color:var(--bad)}
.card.warn{background:var(--warnbg);border-color:var(--warn)}.card.warn .n{color:var(--warn)}
.banner{border-radius:10px;padding:12px 16px;margin:16px 0;border:1px solid}
.banner.ok{background:var(--okbg);border-color:var(--ok);color:var(--ok)}
.banner.bad{background:var(--badbg);border-color:var(--bad);color:var(--bad)}
.banner.warn{background:var(--warnbg);border-color:var(--warn);color:var(--warn)}
.banner b{display:block;margin-bottom:4px}
.empty{color:var(--mut);font-style:italic;padding:10px 0}
footer{margin-top:48px;padding-top:14px;border-top:1px solid var(--line);color:var(--mut);font-size:12.5px}
"""

TITLES = {
    "adopt": "도입 결과",
    "plan": "계획",
    "ready": "준비도 점검",
    "cycle": "사이클 결과",
}


def build(kind):
    smap = rd("docs", "spec", "source-map.md")
    hdr, rows = section_table(smap, 2)
    shdr, srows = section_table(smap, 3)
    parts = []

    if rows:
        parts.append(dashboard(hdr, rows))

    rc, out = check_output()
    if rc is not None:
        cls = "ok" if rc == 0 else "bad"
        label = "정합성 검사 통과" if rc == 0 else "정합성 검사 실패 — 아래 항목을 해결한다"
        detail = ("<pre><code>%s</code></pre>" % html.escape(out.strip())) if out.strip() else ""
        parts.append('<div class="banner %s"><b>%s</b>%s</div>' % (cls, html.escape(label), detail))

    def sect(title, body):
        parts.append("<h2>%s</h2>" % html.escape(title))
        parts.append(body if body.strip() else '<p class="empty">아직 없다.</p>')

    if kind == "adopt":
        sect("요구사항 매핑표", table(hdr, rows) if rows else "")
        sect("화면 매핑표", table(shdr, srows) if srows else "")
        m = re.search(r"^## 4\.(.*?)(?=^## |\Z)", smap, re.M | re.S)
        sect("계약 확인 — 상류가 무엇을 담고 무엇을 안 담나", md(m.group(1)) if m else "")
        sect("상류 수집 기록", md(rd("docs", "upstream", "manifest.tsv")
                              .replace("#", "").strip() or ""))
    elif kind == "plan":
        body = rd("docs", "upstream", "plan.md")
        sect("계획 문서", md(body))
    elif kind == "ready":
        i_id, i_rd = col(hdr, "ID"), col(hdr, "준비")
        i_cd, i_ts = col(hdr, "조건 수"), col(hdr, "테스트")
        i_st = col(hdr, "상태")
        rr = []
        for r in rows:
            c, t = cell(r, i_cd), n_items(cell(r, i_ts))
            cov = "—" if not c.isdigit() else ("%d / %s %s" % (t, c, "✅" if t >= int(c) else "❌"))
            rr.append([cell(r, i_id), cell(r, i_rd) or "점검 전", cov, cell(r, i_st)])
        sect("요구사항별 — 무엇이 되면 됐나 (수용 기준)",
             table(["ID", "준비 (Story 롤업)", "테스트 / 검증 조건", "상태"], rr) if rr else "")
        sect("Story별 — 어떻게 동작하나 (개발 준비 슬롯 12칸)", story_slots())
        sect("슬롯 12칸의 뜻", md(pick_sections(rd("docs", "guides", "ready.md"),
                                            ["개발 준비 슬롯 — 12칸"], with_heading=False)))
    elif kind == "cycle":
        cdir = os.path.join(ROOT, "docs", "plan", "cycles")
        files = sorted(f for f in os.listdir(cdir) if f.endswith(".md") and "template" not in f) \
            if os.path.isdir(cdir) else []
        if files:
            sect("현재 사이클 — %s" % files[-1], md(rd("docs", "plan", "cycles", files[-1])))
        else:
            sect("현재 사이클", "")
        sect("요구사항 매핑표", table(hdr, rows) if rows else "")

    sect("현재 상태", md(status_digest()))

    title = TITLES[kind]
    proj = (re.search(r"^#\s+(.+)$", rd("CLAUDE.md"), re.M) or [None, "프로젝트"])[1]
    return """<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>%s — %s</title><style>%s</style></head><body><div class="wrap">
<header><h1>%s</h1><div class="sub">%s · 생성 %s · <code>.claude/scripts/report.py %s</code></div></header>
%s
<footer><b>이 파일은 정본이 아니다.</b> 정본은 <code>docs/</code> 아래의 md 이고, 이 화면은 매번 다시 생성되는 읽기용 사본이다.
손으로 고치지 말고 md 를 고친 뒤 다시 생성한다.</footer>
</div></body></html>""" % (html.escape(title), html.escape(proj), CSS,
                           html.escape(title), html.escape(proj), date.today().isoformat(),
                           kind, "\n".join(parts))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1 or args[0] not in KINDS:
        print("사용법: report.py <%s> [--open]" % "|".join(KINDS), file=sys.stderr)
        return 2
    kind = args[0]
    outdir = os.path.join(ROOT, "docs", "reports")
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, "%s-%s.html" % (kind, date.today().isoformat()))
    with open(path, "w", encoding="utf-8") as f:
        f.write(build(kind))
    rel = os.path.relpath(path, ROOT)
    print("리포트 생성: %s" % rel)
    print("열기: open %s" % rel)
    if "--open" in sys.argv[1:] and sys.platform == "darwin":
        subprocess.run(["open", path], check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
