#!/usr/bin/env python3
"""check-docs.sh 의 문서·에이전트·셸 검사 (1-c · 5 · 6 · 7 · 8 · 9 · 10 · 11 · 12).

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
PLUGIN = os.path.join(ROOT, "plugins", "mdm")          # 플러그인 정본 (커맨드·에이전트·훅·엔진·제품 양식)
KIT = os.path.join(PLUGIN, "templates")                 # 제품에 심는 문서 — `docs/…` 참조의 기준
COMMANDS = os.path.join(PLUGIN, "commands")
PLUGIN_AGENTS = os.path.join(PLUGIN, "agents")
AGENTS = os.path.join(ROOT, ".claude", "agents")
KITREVIEW = os.path.join(ROOT, ".claude", "commands", "mdm-kit-review.md")

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
        if dp == PLUGIN or dp.startswith(PLUGIN + os.sep):
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
    """플러그인 안의 모든 md — 제품 양식(templates)·커맨드·에이전트·README."""
    out = []
    for dp, dns, fns in os.walk(PLUGIN):
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
TOPS = (".githooks/", ".claude/", ".claude-plugin/", ".github/", "scripts/", "docs/", "plugins/",
        "guides/", "examples/")
# 설치·실행 시점에 **생성되는** 산출물 — 이 저장소에 없는 것이 정상이다.
# 목록으로 좁게 둔다: 넓히면 진짜 깨진 참조가 이 구멍으로 샌다.
GENERATED = ("CLAUDE.md.dev-kit-new", "docs/reports/", "docs/upstream/manifest.tsv", ".dev-kit-1x-retired",
             ".claude/settings.json")   # 제품의 설정 파일 — `mdm init` 이 플러그인 등록을 써 넣는다. 이 저장소에는 없다
# 2.0.0 이 옮긴 옛 경로 — **이력 문서(CHANGELOG·docs/history)에서만** 살아 있는 참조로 인정한다.
# 그 밖의 문서가 옛 경로를 쓰면 깨진 참조다 (2.0.0 뒤에 쓴 문서는 새 경로를 알아야 한다).
RETIRED_PREFIXES = ("templates/dev-kit/", ".claude/")   # 옛 배포본은 제품의 .claude/ 에 키트 파일을 두었다
HISTORICAL = ("CHANGELOG.md", "docs/history/")
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
            if rel(f).startswith(HISTORICAL) and tok.startswith(RETIRED_PREFIXES):
                continue
            if not os.path.exists(os.path.join(ROOT, tok)) and not os.path.exists(os.path.join(KIT, tok)):
                bad("깨진 참조(저장소 자신): %s → `%s`" % (rel(f), tok))
    if seen == 0:
        bad("검사 1-c 가 백틱 경로를 한 건도 찾지 못했다 — 추출이 깨졌다 (통과로 위장하지 않는다)")


# ── 5. 「절 이름」 포인터 ────────────────────────────────────────────────
# 연결 어구 길이에 상한을 두지 않는다 — 13자를 넘는 포인터가 조용히 빠졌다(#146).
# 백틱과 개행만 경계로 쓴다.
# 연결 어구에 **길이 상한은 두지 않되**(13자 초과 포인터가 조용히 빠졌다 — #146),
# 괄호·쉼표가 끼면 포인터가 아니라 서술문이다: `…STATUS.md` 머리말 (두 곳 다 — 아래 「정하는 법」)
# 처럼 **자기 문서의 절**을 가리키는 형태가 그렇다. 그때 "인용한 문서 자신도 후보"로 완화했더니
# 검사 5 가 통째로 뚫렸다(2회전 K2: `## 언제 도나` 개명이 5종 전부 통과). 형태로 거른다.
POINTER = re.compile(r"`([^`\n]+\.md)`([^`\n「()（）,，]*)「([^」\n]+)」")


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
            for t in targets:
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
RPT = os.path.join(PLUGIN, "scripts", "report.py")


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
        bad("mdm-kit-review.md 가 없다: %s" % rel(KITREVIEW))
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
            bad("mdm-kit-review.md 표가 없는 에이전트를 가리킨다: %s (축 %s)" % (agent, axis))
            continue
        # 축 열 ↔ 에이전트 이름이 어긋나면 오배선이다 — 표만 보고는 안 드러난다
        m = re.fullmatch(r"mdm-kit-review-k(\d+)", agent)
        if m and m.group(1) != axis[1:]:
            bad("축 오배선: 표의 축 %s 행이 `%s` 를 가리킨다 (축 번호와 에이전트 번호가 다르다)"
                % (axis, agent))

    for n, p in sorted(names.items()):
        if n.startswith("mdm-kit-review-") and n not in table.values():
            bad("에이전트가 mdm-kit-review.md 축 표에 없다 (그 축은 안 돌아간다): %s" % n)
        elif not n.startswith("mdm-kit-review-") and "`%s`" % n not in krv:
            bad("에이전트가 mdm-kit-review.md 어디에도 없다: %s (%s)" % (n, rel(p)))


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
              os.path.join(PLUGIN, "scripts"), os.path.join(PLUGIN, "hooks"), os.path.join(PLUGIN, "bin")):
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            p = os.path.join(d, fn)
            if os.path.isfile(p) and (fn.endswith(".sh") or d.endswith(".githooks") or d.endswith("bin")):
                out.append(p)
    return out


# awk 프로그램은 **여러 줄에 걸친다** — 이 저장소의 awk 가 대부분 그렇고, 하필 #098 을 낳은
# `check-consistency.sh` 의 `table_of()` 가 정확히 그 모양이다. 줄 단위로 보면 재발을 못 잡는다(2회전 K2·K3).
AWK_PROG = re.compile(r"\bawk\b(?:[^'\n]*)'((?:[^'])*)'", re.S)


def _strip_comments(text):
    return "\n".join("" if l.lstrip().startswith("#") else l for l in text.split("\n"))


def check_10():
    for p in repo_shell():
        body = read(p)
        stripped = _strip_comments(body)   # 줄 수는 보존된다 — 오프셋도 이 텍스트에서 센다
        for m in AWK_PROG.finditer(stripped):
            prog = m.group(1)
            if "==" in prog and NON_ASCII.search(prog):
                line = stripped[:m.start()].count("\n") + 1
                bad("%s:%d — awk 프로그램이 비ASCII 문자열을 `==` 로 비교한다(여러 줄 포함). "
                    "BSD awk(macOS 기본)는 비ASCII 문자열 둘을 무조건 같다고 판정한다 → 순수 bash 로 비교한다"
                    % (rel(p), line))
        for i, ln in enumerate(body.split("\n"), 1):
            if ln.lstrip().startswith("#"):
                continue  # 설명하는 주석은 대상이 아니다
            if VAR_MB.search(ln):
                bad("%s:%d — `$변수` 뒤에 곧바로 멀티바이트 문자가 온다. "
                    "bash 가 그 바이트를 변수명에 붙여 읽어 `set -u` 아래에서 죽는다 → `${변수}` 로 감싼다"
                    % (rel(p), i))



# ── 11. 플러그인 이름 공간 정합 ────────────────────────────────────────
# 0.7.0 은 충돌을 피하려고 파일명에 `mdm-` 을 붙였다. 2.0.0 부터 그 몫은 플러그인 이름 공간(`/mdm:adopt` ·
# `mdm:code-review`)이 한다 — 파일명에 접두가 남으면 `/mdm:mdm-adopt` 가 된다(실측). 이름 공간이 생기면서
# 새 결함 유형이 생겼다: 문서가 부르는 `/mdm:<이름>` 이 실재하지 않거나, 제품에 더는 없는 `.claude/scripts/…`
# 경로·옛 이름이 제품 양식에 남는 것이다 (제품에서는 `mdm ops refs` 가 그것을 깨진 참조로 잡아 **사용자 과실처럼** 보고한다).
SLASH_CMD = re.compile(r"/mdm:([a-z][a-z0-9-]*)")
AGENT_REF = re.compile(r"`mdm:([a-z][a-z0-9-]*)`")
OLD_NAMES = re.compile(r"(?<![\w:-])/mdm-(adopt|plan|ready|review|stage|cycle-close|ingest-errors)\b"
                       r"|(?<![\w:-])mdm-(code-review|error-learning)(?![\w-])")
PRODUCT_MISSING = re.compile(r"\.claude/(commands|agents|hooks|scripts)/")
# 제품이 부를 수 없는 엔진 파일을 맨 이름으로 부르는 산문 — 1.x 경로 치환이 백틱 안의 맨 이름을 놓쳤다(issues #435).
# 엔진 파일을 **설명**하는 것(`check-plan.py` 등)은 허용하고, 사람이 실행하라고 적는 두 진입점만 본다.
BARE_ENTRY = re.compile(r"(?<![\w/.-])(mdm-check|check-consistency)\.sh")


def _plugin_md(sub):
    d = os.path.join(PLUGIN, sub)
    out = []
    for dp, dns, fns in os.walk(d):
        dns[:] = [x for x in dns if x != ".git"]
        for fn in sorted(fns):
            if fn.endswith(".md"):
                out.append(os.path.join(dp, fn))
    return out


def check_11():
    seen = 0
    names = {}
    for sub in ("commands", "agents"):
        d = os.path.join(PLUGIN, sub)
        if not os.path.isdir(d):
            bad("플러그인 %s 디렉토리가 없다: %s — 검사 11 이 그 몫을 못 본다 (조용히 넘어가지 않는다)"
                % (sub, rel(d)))
            continue
        names[sub] = set()
        for p in _plugin_md(sub):
            fn = os.path.basename(p)
            seen += 1
            base = fn[:-3]
            if base.startswith("mdm-"):
                bad("플러그인 %s 파일명에 `mdm-` 접두가 남았다: %s — 이름 공간은 플러그인이 붙인다 (이대로면 `/mdm:%s` 가 된다)"
                    % (sub, rel(p), base))
            n = fm_name(p)
            if n and n.startswith("mdm-"):
                bad("플러그인 %s 의 name 에 `mdm-` 접두가 남았다: %s (%s)" % (sub, n, rel(p)))
            if sub == "agents" and n and n != base:
                bad("플러그인 에이전트 파일명과 name 이 다르다: %s vs %s (%s)" % (base, n, rel(p)))
            names[sub].add(base)
    if seen == 0:
        bad("검사 11 이 플러그인 커맨드·에이전트를 한 건도 찾지 못했다 — 추출이 깨졌다 (통과로 위장하지 않는다)")
        return
    # 참조 실재 — 플러그인 안의 모든 md (양식·커맨드·에이전트·README)
    refs = 0
    for f in kit_docs():
        body = read(f)
        for m in SLASH_CMD.findall(body):
            refs += 1
            if "commands" in names and m not in names["commands"]:
                bad("문서가 없는 커맨드를 부른다: %s → `/mdm:%s` (plugins/mdm/commands/%s.md 가 없다)" % (rel(f), m, m))
        for m in AGENT_REF.findall(body):
            refs += 1
            if "agents" in names and m not in names["agents"]:
                bad("문서가 없는 서브에이전트를 가리킨다: %s → `mdm:%s` (plugins/mdm/agents/%s.md 가 없다)" % (rel(f), m, m))
    if refs == 0:
        bad("검사 11 이 `/mdm:…`·`mdm:…` 참조를 한 건도 찾지 못했다 — 추출이 깨졌다 (통과로 위장하지 않는다)")
    # 제품 양식·커맨드·에이전트에 제품에 없는 경로·옛 이름이 남았는가 (README 는 1.x 이관 절에서 옛 경로를 설명하므로 제외)
    for sub in ("templates", "commands", "agents"):
        for f in _plugin_md(sub):
            for i, ln in enumerate(read(f).split("\n"), 1):
                if PRODUCT_MISSING.search(ln):
                    bad("%s:%d — 제품에 없는 경로를 가리킨다 (`.claude/{commands,agents,hooks,scripts}/` 는 2.0.0 부터 플러그인이 제공한다 — `mdm …`·`/mdm:…` 으로 쓴다)"
                        % (rel(f), i))
                m = BARE_ENTRY.search(ln)
                if m:
                    bad("%s:%d — 제품에 없는 엔진 파일을 부른다: `%s` (제품에서는 `mdm final`·`mdm check` 로 쓴다)" % (rel(f), i, m.group(0)))
                m = OLD_NAMES.search(ln)
                if m:
                    bad("%s:%d — 1.x 이름이 남았다: `%s` (2.0.0 은 `/mdm:<이름>`·`mdm:<이름>`)" % (rel(f), i, m.group(0)))


# ── 12. 플러그인 매니페스트 정합 ────────────────────────────────────────
# 버전이 네 곳에 적힌다 — plugin.json · 제품 CLAUDE.md 스탬프 · marketplace.json 항목 · 제품 CI 양식의 MDM_KIT_REF 핀.
# 하나만 올리면 설치기가 「배포본이 깨졌다」로 죽거나(스탬프≠plugin.json), 제품 CI 가 다른 엔진으로 판정한다(핀).
# hooks.json 이 없는 훅을 가리키면 Claude Code 는 조용히 아무것도 안 돈다 — 훅 셋이 전부 꺼진 채 조용하다.
def check_12():
    import json
    def load(p):
        try:
            with open(p, encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError) as e:
            bad("JSON 을 읽을 수 없다: %s (%s)" % (rel(p), e))
            return None
    pj = load(os.path.join(PLUGIN, ".claude-plugin", "plugin.json"))
    mk = load(os.path.join(ROOT, ".claude-plugin", "marketplace.json"))
    hk = load(os.path.join(PLUGIN, "hooks", "hooks.json"))
    if pj is None or mk is None or hk is None:
        return
    ver = pj.get("version")
    if not isinstance(ver, str) or not ver:
        bad("plugin.json 에 version 이 없다")
        return
    if pj.get("name") != "mdm":
        bad("plugin.json 의 name 이 `mdm` 이 아니다: %r — 커맨드 이름 공간(`/mdm:…`)·문서 전부가 이 이름을 전제한다" % pj.get("name"))
    m = re.search(r"dev-kit v([0-9][\w.\-]*)", read(os.path.join(KIT, "CLAUDE.md")).split("\n", 1)[0])
    stamp = m.group(1) if m else None
    if stamp != ver:
        bad("버전 불일치: plugin.json %s vs templates/CLAUDE.md 첫 줄 스탬프 %s — 설치기가 배포본이 깨졌다고 죽는다" % (ver, stamp))
    entries = [e for e in mk.get("plugins", []) if isinstance(e, dict) and e.get("name") == "mdm"]
    if not entries:
        bad("marketplace.json 에 `mdm` 항목이 없다")
    else:
        e = entries[0]
        if e.get("version") != ver:
            bad("버전 불일치: marketplace.json 의 mdm 항목 %s vs plugin.json %s" % (e.get("version"), ver))
        src = e.get("source")
        if not (isinstance(src, str) and os.path.isdir(os.path.join(ROOT, src))):
            bad("marketplace.json 의 mdm source 가 실재하는 디렉토리가 아니다: %r" % src)
    if (mk.get("metadata") or {}).get("version") not in (None, ver):
        bad("버전 불일치: marketplace.json 의 metadata.version %s vs plugin.json %s" % (mk["metadata"]["version"], ver))
    # 다른 에이전트·README 가 clone 할 엔진 판 — 제품 AGENTS.md 는 Codex 등이 어느 엔진을 받을지 정한다(issues #433)
    for doc in [os.path.join(KIT, "AGENTS.md"), os.path.join(PLUGIN, "README.md")]:
        for pin in re.findall(r"--branch v([0-9][\w.\-]*)", read(doc)):
            if pin != ver:
                bad("버전 불일치: %s 의 --branch v%s vs plugin.json %s — 그 안내대로 clone 하면 다른 엔진을 받는다" % (rel(doc), pin, ver))
    ci = read(os.path.join(KIT, ".github", "workflows", "mdm-check.yml"))
    m = re.search(r"MDM_KIT_REF:\s*[\"']?v?([0-9][\w.\-]*)", ci)
    pin = m.group(1) if m else None
    if pin != ver:
        bad("버전 불일치: 제품 CI 양식의 MDM_KIT_REF 핀 %s vs plugin.json %s — 새로 설치한 제품의 CI 가 다른 엔진을 받는다" % (pin, ver))
    cmds = 0
    for event, groups in (hk.get("hooks") or {}).items():
        for g in groups or []:
            for h in g.get("hooks") or []:
                cmd = str(h.get("command", ""))
                cmds += 1
                m = re.search(r"\$\{CLAUDE_PLUGIN_ROOT\}/([^\s\"']+)", cmd)
                if not m:
                    bad("hooks.json %s 의 command 가 ${CLAUDE_PLUGIN_ROOT}/… 형태가 아니다: %r" % (event, cmd))
                    continue
                target = os.path.join(PLUGIN, m.group(1))
                if not os.path.isfile(target):
                    bad("hooks.json %s 가 없는 훅을 가리킨다: %s — 그 훅은 조용히 안 돈다" % (event, m.group(1)))
                elif not os.access(target, os.X_OK):
                    bad("hooks.json %s 가 가리키는 훅에 실행 권한이 없다: %s" % (event, m.group(1)))
    if cmds == 0:
        bad("hooks.json 에 훅이 하나도 없다 — 훅 셋(의존성·비밀값·STATUS)이 전부 꺼진다")
    launcher = os.path.join(PLUGIN, "bin", "mdm")
    if not (os.path.isfile(launcher) and os.access(launcher, os.X_OK)):
        bad("plugins/mdm/bin/mdm 런처가 없거나 실행 권한이 없다 — 문서의 `mdm …` 명령 전부가 죽는다")


for fn in (check_1c, check_5, check_6, check_7, check_8, check_9, check_10, check_11, check_12):
    fn()

for m in problems:
    print(m)
sys.exit(1 if problems else 0)
