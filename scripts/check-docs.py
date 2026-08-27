#!/usr/bin/env python3
"""check-docs.sh 의 문서·에이전트·셸 검사 (1-c · 5 · 6 · 7 · 8 · 9 · 10).

**왜 bash+grep 이 아닌가.** 로케일 때문이다 — `[^「]` 같은 부정 문자클래스는 C/POSIX 로케일에서
**바이트 클래스**가 되어 `—`(E2 80 94)·`…`(E2 80 A6)·`가`(EA B0 80) 안의 바이트 `0x80` 에 걸린다.
그러면 추출이 0건이 되고 검사는 아무 일 없다는 듯 "통과"를 출력한다 (이슈 #101).
파이썬은 인코딩을 명시적으로 다루므로 로케일에 흔들리지 않는다.
BSD awk 의 한글 `==` 버그(이슈 #098)도 같은 이유로 피한다.

**추출이 0건이면 실패다** (이슈 #102). 검사가 스스로 무장해제한 것을 통과로 위장하지 않는다 —
루트 CLAUDE.md 「이 저장소에서 밟은 셸 함정」 3번이 규칙으로 선언한 것이다.

각 검사가 붉어지는 증거는 `scripts/test-docs-check.sh` 에 있다 (이슈 #103).
"""
import ast
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
KIT = os.path.join(ROOT, "templates", "dev-kit")
AGENTS = os.path.join(ROOT, ".claude", "agents")
KITREVIEW = os.path.join(ROOT, ".claude", "commands", "kit-review.md")

problems = []


def bad(msg):
    problems.append(msg)


def rel(p):
    return os.path.relpath(p, ROOT)


def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


# ── 대상 파일 목록 ────────────────────────────────────────────────────────
def _ignored(paths):
    """.gitignore 된 로컬 전용 문서를 뺀다. git 이 없으면 **아무것도 빼지 않는 대신 알린다** —
    조용히 다른 집합을 검사하면 로컬과 CI 가 어긋난다."""
    import subprocess
    try:
        r = subprocess.run(["git", "-C", ROOT, "check-ignore", "--stdin", "--non-matching", "--verbose"],
                           input="\n".join(paths), capture_output=True, text=True)
    except OSError:
        return None
    if r.returncode not in (0, 1):
        return None
    keep = [l[3:] for l in r.stdout.split("\n") if l.startswith("::\t")]
    return keep


def repo_docs():
    out = []
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in (".git", "manyfast_reference", "node_modules")]
        if dp == KIT or dp.startswith(KIT + os.sep):
            continue
        for fn in fns:
            if fn.endswith(".md"):
                out.append(os.path.join(dp, fn))
    kept = _ignored(out)
    if kept is None:
        print("알림: git check-ignore 를 쓸 수 없어 로컬 전용 문서까지 검사한다 (오탐이 날 수 있다)",
              file=sys.stderr)
        return sorted(out)
    return sorted(kept)


def kit_docs():
    out = []
    for dp, dns, fns in os.walk(KIT):
        dns[:] = [d for d in dns if d != ".git"]
        for fn in fns:
            if fn.endswith(".md"):
                out.append(os.path.join(dp, fn))
    return sorted(out)


def all_md():
    return repo_docs() + kit_docs()


PLACEHOLDER = re.compile(r"[<>*…]|C00-이름|ADR-000")


# ── 1-c. 이 저장소 자신의 백틱 경로 ──────────────────────────────────────
# 확장자 목록으로 좁히지 않는다 — 하필 절대 규칙 1의 장치 경로(`.githooks/pre-commit`)가
# 무확장자이고(#117), 한글이 섞인 경로도 있다(#148). 대신 **저장소 최상위 이름으로 시작하는
# 슬래시 포함 토큰**을 대상으로 삼는다. 경로는 이 저장소 기준이거나 키트 기준이면 통과한다 —
# 루트 문서는 둘 다 인용한다(`scripts/…`는 이 저장소, `docs/…`는 제품 저장소가 가질 키트 문서).
TOPS = (".githooks/", ".claude/", ".github/", "scripts/", "docs/", "templates/",
        "guides/", "examples/")
# 설치·실행 시점에 **생성되는** 산출물 — 이 저장소에 없는 것이 정상이다.
# 목록으로 좁게 둔다: 넓히면 진짜 깨진 참조가 이 구멍으로 샌다.
GENERATED = ("settings.json.dev-kit", "CLAUDE.md.dev-kit-new", "docs/reports/",
             "docs/upstream/manifest.tsv")
BACKTICK = re.compile(r"`([^`\n]+)`")


def check_1c():
    seen = 0
    for f in repo_docs():
        for tok in BACKTICK.findall(read(f)):
            tok = tok.strip()
            if "/" not in tok or " " in tok or tok.endswith("/"):
                continue
            if not tok.startswith(TOPS):
                continue
            if PLACEHOLDER.search(tok):
                continue
            if any(g in tok for g in GENERATED):
                continue
            seen += 1
            if not os.path.exists(os.path.join(ROOT, tok)) and not os.path.exists(os.path.join(KIT, tok)):
                bad("깨진 참조(저장소 자신): %s → `%s`" % (rel(f), tok))
    if seen == 0:
        bad("검사 1-c 가 백틱 경로를 한 건도 찾지 못했다 — 추출이 깨졌다 (통과로 위장하지 않는다)")


# ── 5. 「절 이름」 포인터 ────────────────────────────────────────────────
# 연결 어구 길이에 상한을 두지 않는다 — 13자를 넘는 포인터가 조용히 빠졌다(#146).
# 백틱과 개행만 경계로 쓴다.
POINTER = re.compile(r"`([^`\n]+\.md)`([^`\n「]*)「([^」\n]+)」")


def doc_labels(path):
    """그 파일이 **라벨로 쓰는** 문자열들. 산문에 스쳐 지나가는 인용은 라벨이 아니다."""
    out = []
    for ln in read(path).split("\n"):
        m = re.match(r"\s*#{1,6}\s+(.*)$", ln)
        if m:
            out.append(m.group(1).strip())
        # `**라벨**` — 줄머리, 인용구(`> `), 목록(`- `·`* `·`1. `) 뒤도 포함한다 (#113)
        m = re.match(r"\s*(?:[>\-*]\s+|\d+\.\s+|[>\s]*)\*\*([^*]+)\*\*", ln)
        if m:
            out.append(m.group(1).strip())
        if ln.lstrip().startswith("|"):
            for cell in ln.split("|"):
                out.append(cell.strip().strip("*").strip())
    return [x for x in out if x]


def resolve_docs(ref):
    """참조 경로가 가리킬 수 있는 **모든** 후보. 맨 파일명이면 동명 파일을 전부 준다 —
    임의로 하나만 고르면 오탐·미탐이 양방향으로 난다 (#114)."""
    if "/" in ref:
        return [p for p in (os.path.join(ROOT, ref), os.path.join(KIT, ref)) if os.path.exists(p)]
    base = os.path.basename(ref)
    return [p for p in all_md() if os.path.basename(p) == base]


def check_5():
    seen = 0
    labels_cache = {}
    for f in all_md():
        for ref, gap, sect in POINTER.findall(read(f)):
            if PLACEHOLDER.search(ref):
                continue
            targets = resolve_docs(ref)
            if not targets:
                continue  # 파일 자체가 없는 것은 1)·1-c) 의 몫 — 겹쳐 보고하지 않는다
            seen += 1
            hit = False
            for t in targets + [f]:   # 인용한 문서 자신도 후보다 — "아래 「…」" 형태가 실재한다
                if t not in labels_cache:
                    labels_cache[t] = doc_labels(t)
                if any(lb.startswith(sect) for lb in labels_cache[t]):
                    hit = True
                    break
            if not hit:
                bad("끊긴 절 포인터: %s → `%s` 「%s」 (그 이름의 절·라벨이 대상 파일에 없다)"
                    % (rel(f), ref, sect))
    if seen == 0:
        bad("검사 5 가 절 포인터를 한 건도 찾지 못했다 — 추출이 깨졌다 (통과로 위장하지 않는다)")


# ── 6. report.py 가 하드코딩한 절 이름 ──────────────────────────────────
# **대상 파일을 해석한다.** 키트 전체 헤딩을 한 통에 모아 접두 매칭하면 동명 헤딩에 가려
# 개명이 조용히 통과한다(#110) — 하필 그 예가 이번에 고친 #090 과 같은 자리였다.
RPT = os.path.join(KIT, ".claude", "scripts", "report.py")


def _rd_path(node, assigns):
    """`rd("docs","status","STATUS.md")` → 키트 기준 경로. 변수면 그 변수의 대입을 따라간다."""
    if isinstance(node, ast.Name):
        node = assigns.get(node.id)
        if node is None:
            return None
    if not (isinstance(node, ast.Call) and getattr(node.func, "id", "") == "rd"):
        return None
    parts = []
    for a in node.args:
        if isinstance(a, ast.Constant) and isinstance(a.value, str):
            parts.append(a.value)
        else:
            parts.append("*")          # 루프 변수 등 — 양식으로 대신 본다
    p = os.path.join(KIT, *parts)
    if "*" in parts:
        d = os.path.dirname(p)
        for cand in ("C00-template.md", "ST-000-template.md"):
            if os.path.exists(os.path.join(d, cand)):
                return os.path.join(d, cand)
        return None
    return p


def check_6():
    if not os.path.exists(RPT):
        bad("report.py 가 없다: %s" % rel(RPT))
        return
    tree = ast.parse(read(RPT))
    assigns = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            assigns[node.targets[0].id] = node.value
    seen = 0
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and getattr(node.func, "id", "") == "pick_sections"):
            continue
        if len(node.args) < 2:
            continue
        target = _rd_path(node.args[0], assigns)
        names = []
        arg = node.args[1]
        if isinstance(arg, ast.Name):
            arg = assigns.get(arg.id, arg)
        if isinstance(arg, (ast.List, ast.Tuple)):
            names = [e.value for e in arg.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)]
        lv = 2
        for kw in node.keywords:
            if kw.arg == "lv" and isinstance(kw.value, ast.Constant):
                lv = kw.value.value
        if not names:
            bad("report.py 의 pick_sections 호출에서 절 이름을 뽑지 못했다 (상수 리스트로 두거나 이 검사를 넓힌다)")
            continue
        if target is None:
            bad("report.py 의 pick_sections 대상 파일을 해석하지 못했다: %s" % names)
            continue
        heads = [re.sub(r"^#+\s+", "", l) for l in read(target).split("\n")
                 if re.match(r"^#{%d}\s" % lv, l)]
        for nm in names:
            seen += 1
            if not any(h.startswith(nm) for h in heads):
                bad('report.py 가 없는 절을 찾는다: "%s" — %s 에 그 제목의 h%d 헤딩이 없다'
                    % (nm, rel(target), lv))
    if seen == 0:
        bad("검사 6 이 절 이름을 한 건도 찾지 못했다 — 추출이 깨졌다 (통과로 위장하지 않는다)")


# ── 7. 축 ↔ 에이전트 ────────────────────────────────────────────────────
# **표를 실제로 파싱한다.** 파일 전체 grep 이면 축 행을 지워도 산문에 이름이 남으면 통과하고,
# 축 열을 뒤바꾼 **오배선**은 원리적으로 못 잡는다 (#131).
AXIS_ROW = re.compile(r"^\|\s*(K\d+)\s*\|\s*`([A-Za-z0-9_-]+)`\s*\|")


def agent_files():
    out = []
    for dp, dns, fns in os.walk(AGENTS):
        dns[:] = [d for d in dns if d != ".git"]
        for fn in fns:
            if fn.endswith(".md"):
                out.append(os.path.join(dp, fn))
    return sorted(out)


def frontmatter(path):
    s = read(path)
    m = re.match(r"---\n(.*?)\n---\n", s, re.S)
    return m.group(1) if m else ""


def fm_name(path):
    m = re.search(r"^name:\s*(\S+)", frontmatter(path), re.M)
    return m.group(1) if m else ""


def check_7():
    if not os.path.isdir(AGENTS):
        bad("에이전트 디렉토리가 없다: %s — 축↔에이전트 검사가 꺼진다 (조용히 넘어가지 않는다)" % rel(AGENTS))
        return
    if not os.path.exists(KITREVIEW):
        bad("kit-review.md 가 없다: %s" % rel(KITREVIEW))
        return
    krv = read(KITREVIEW)
    table = {}
    for ln in krv.split("\n"):
        m = AXIS_ROW.match(ln)
        if m:
            table[m.group(1)] = m.group(2)
    if not table:
        bad("검사 7 이 축↔에이전트 표를 한 행도 찾지 못했다 — 표 형식이 바뀌었다 (통과로 위장하지 않는다)")
        return

    files = agent_files()
    names = {}
    for p in files:
        b = os.path.basename(p)[:-3]
        n = fm_name(p)
        if n and n != b:
            bad("에이전트 파일명과 name 이 다르다: %s vs %s (%s)" % (b, n, rel(p)))
        names[n or b] = p

    for axis, agent in sorted(table.items()):
        if agent not in names:
            bad("kit-review.md 표가 없는 에이전트를 가리킨다: %s (축 %s)" % (agent, axis))
            continue
        # 축 열 ↔ 에이전트 이름이 어긋나면 오배선이다 — 표만 보고는 안 드러난다
        m = re.fullmatch(r"kit-review-k(\d+)", agent)
        if m and m.group(1) != axis[1:]:
            bad("축 오배선: 표의 축 %s 행이 `%s` 를 가리킨다 (축 번호와 에이전트 번호가 다르다)"
                % (axis, agent))

    for n, p in sorted(names.items()):
        if n.startswith("kit-review-") and n not in table.values():
            bad("에이전트가 kit-review.md 축 표에 없다 (그 축은 안 돌아간다): %s" % n)
        elif not n.startswith("kit-review-") and "`%s`" % n not in krv:
            bad("에이전트가 kit-review.md 어디에도 없다: %s (%s)" % (n, rel(p)))


# ── 8. (로컬 전용) issues.md 이슈 번호 유일성 ──────────────────────────
# 표기 변형(공백 수·굵게)에 흔들리지 않게 관대하게 읽는다 (#149).
ISSUE_ROW = re.compile(r"^\|\s*\*{0,2}(#\d{3})\*{0,2}\s*\|", re.M)


def check_8():
    p = os.path.join(ROOT, "issues.md")
    if not os.path.exists(p):
        return  # .gitignore 대상 — CI 에는 없다
    nums = ISSUE_ROW.findall(read(p))
    if not nums:
        bad("검사 8 이 이슈 행을 한 건도 찾지 못했다 — 표 형식이 바뀌었다 (통과로 위장하지 않는다)")
        return
    seen, dup = set(), set()
    for n in nums:
        (dup if n in seen else seen).add(n)
    for n in sorted(dup):
        bad("issues.md 이슈 번호 중복: %s (번호는 재사용하지 않는다 — 다음 번호는 전체 최대값+1)" % n)


# ── 9. 쓰기 도구를 가진 에이전트의 임시 디렉토리 제한 ──────────────────
# `tools:` **줄이 없으면 도구를 전부 상속한다** — 가장 관대한 경우가 검사에서 빠지면
# 검사가 위험도와 역상관이 된다 (#115①). YAML 블록 리스트(②)·`Edit`(③)도 같은 대상이다.
# 이 검사가 보장하는 것은 **그 절차 문장이 조용히 사라지지 않는다**까지다 —
# 샌드박스가 없으므로 경로 제한 자체는 끝까지 절차다 (루트 CLAUDE.md 절대 규칙 3).
# 그리고 쓰기 도구를 안 주는 것이 **파일을 못 쓰게 만드는 것은 아니다** — 모든 리뷰 에이전트가
# `Bash` 를 갖고 있고 Bash 는 임의 경로에 쓴다(#152). 이 검사는 '도구 목록'이 아니라
# **'제한을 적어 뒀는가'**를 볼 뿐이다.
WRITE_TOOLS = ("Write", "Edit", "NotebookEdit", "MultiEdit")


def can_write(path):
    fm = frontmatter(path)
    m = re.search(r"^tools:(.*?)(?=^\S|\Z)", fm + "\n", re.M | re.S)
    if not m:
        return True   # 미지정 = 전체 상속
    return any(t in m.group(1) for t in WRITE_TOOLS)


def check_9():
    if not os.path.isdir(AGENTS):
        bad("에이전트 디렉토리가 없다: %s — 임시 디렉토리 제한 검사가 꺼진다 (조용히 넘어가지 않는다)" % rel(AGENTS))
        return
    for p in agent_files():
        if not can_write(p):
            continue
        if "mktemp -d" not in read(p):
            bad("쓰기 도구를 가진 에이전트에 임시 디렉토리 제한이 없다: %s (`mktemp -d` 문장)" % rel(p))


# ── 10. 이 저장소에서 밟은 셸 함정 ─────────────────────────────────────
# 주석은 재발을 못 막는다 — `check-consistency.sh:33` 에 경고가 있었는데도 밟았다 (이슈 #104).
VAR_MB = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]")
NON_ASCII = re.compile(r"[^\x00-\x7F]")


def repo_shell():
    out = []
    for d in (os.path.join(ROOT, "scripts"), os.path.join(ROOT, ".githooks"),
              os.path.join(ROOT, ".claude", "scripts"),
              os.path.join(KIT, ".claude", "scripts"), os.path.join(KIT, ".claude", "hooks")):
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            p = os.path.join(d, fn)
            if os.path.isfile(p) and (fn.endswith(".sh") or d.endswith(".githooks")):
                out.append(p)
    return out


def check_10():
    for p in repo_shell():
        for i, ln in enumerate(read(p).split("\n"), 1):
            if ln.lstrip().startswith("#"):
                continue  # 설명하는 주석은 대상이 아니다
            if VAR_MB.search(ln):
                bad("%s:%d — `$변수` 뒤에 곧바로 멀티바이트 문자가 온다. "
                    "bash 가 그 바이트를 변수명에 붙여 읽어 `set -u` 아래에서 죽는다 → `${변수}` 로 감싼다"
                    % (rel(p), i))
            # 줄에 `awk`·`==`·한글이 같이 있다는 것만으로 잡으면 **설명 문장까지** 걸린다.
            # awk 호출 뒤의 **따옴표로 묶인 프로그램 본문**만 본다.
            m = re.search(r"\bawk\b(.*)$", ln)
            if m:
                for a, b in re.findall(r"'([^']*)'|\"([^\"]*)\"", m.group(1)):
                    prog = a or b
                    if "==" in prog and NON_ASCII.search(prog):
                        bad("%s:%d — awk 프로그램이 비ASCII 문자열을 `==` 로 비교한다. "
                            "BSD awk(macOS 기본)는 비ASCII 문자열 둘을 무조건 같다고 판정한다 → 순수 bash 로 비교한다"
                            % (rel(p), i))
                        break


for fn in (check_1c, check_5, check_6, check_7, check_8, check_9, check_10):
    fn()

for m in problems:
    print(m)
sys.exit(1 if problems else 0)
