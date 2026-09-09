#!/usr/bin/env python3
"""Shared source-map reader. Markdown prose stays authored; table cells are data.

This is a deliberately bounded table format, not a general Markdown renderer.
Numbered H2 sections, pipe tables, fences/comments, escaped pipes and <br> are
supported. Strict consumers reject missing/ambiguous sections and malformed rows.
"""
import re


class ModelError(ValueError):
    pass


def visible_indexed_lines(text):
    fence = None
    comment = False
    for index, raw in enumerate(text.splitlines()):
        line = raw.lstrip(' ')
        # Indented code cannot open an HTML comment or fence.
        if raw.startswith(('    ', '\t')):
            continue
        match = re.match(r'^(`{3,}|~{3,})(.*)$', line)
        if fence:
            if match and match[1][0] == fence[0] and len(match[1]) >= len(fence) and not match[2].strip():
                fence = None
            continue
        if match and not comment:
            fence = match[1]
            continue
        out = ''
        while line:
            if comment:
                end = line.find('-->')
                if end < 0:
                    line = ''
                    break
                line, comment = line[end + 3:], False
            else:
                start = line.find('<!--')
                if start < 0:
                    out += line
                    break
                out += line[:start]
                line, comment = line[start + 4:], True
        yield index, out.strip()


def visible_lines(text):
    for _, line in visible_indexed_lines(text):
        yield line


def split_row(line):
    parts = re.split(r'(?<!\\)\|', line.strip())
    if parts and not parts[0]:
        parts.pop(0)
    if parts and not parts[-1].strip():
        parts.pop()
    return [p.strip().replace('\\|', '|').replace('&#124;', '|') for p in parts]


def placeholder(value):
    return bool(re.fullmatch(r'<[^<>]*>', value.strip()))


def section_table(text, num, strict=False, with_span=False):
    active = False
    found = 0
    header = []
    rows = []
    in_table = False
    ended = False
    start = end = None
    for index, line in visible_indexed_lines(text):
        if re.match(r'^#{1,2}\s', line):
            active = bool(re.match(r'^##\s+%d\.\s' % num, line))
            if active:
                found += 1
                if found > 1 and strict:
                    raise ModelError('중복 절: %s' % num)
            in_table = False
            continue
        if not active or ended:
            continue
        if not line:
            continue
        if not in_table:
            if not line.startswith('|'):
                continue
            cells = split_row(line)
            if 'ID' not in cells:
                continue
            header, in_table = cells, True
            start, end = index, index + 1
            if strict and len(set(header)) != len(header):
                raise ModelError('중복 열 이름')
            continue
        if not line.startswith('|'):
            ended = True
            continue
        cells = split_row(line)
        end = index + 1
        if cells and all(re.fullmatch(r':?-+:?', c) for c in cells):
            continue
        if strict and len(cells) != len(header):
            raise ModelError('표의 열 수가 머리행과 다르다')
        ident = cells[header.index('ID')] if header.index('ID') < len(cells) else ''
        if placeholder(ident):
            continue
        rows.append(cells)
    if strict and (found != 1 or not header):
        raise ModelError('source-map %s절 또는 ID 표가 없다' % num)
    if with_span:
        return header, rows, (start, end)
    return header, rows


REQUIRED = ['ID', '출처', '화면', '준비', '마일스톤', '사이클', '조건 수', '테스트', '상태', '재검토']
STATES = ['⬜ 대기', '🔵 진행 중', '🟡 검수 대기', '✅ 완료', '⛔ 막힘', '취소']
ACTIVE = STATES[1:4]


def items(value):
    return [x.strip() for x in value.split(',') if x.strip() not in ('', '-', '—')]


def read_map(text, strict=False):
    hdr, rows = section_table(text, 2, strict)
    shdr, srows = section_table(text, 3, strict)
    if strict:
        missing = set(REQUIRED) - set(hdr)
        if missing:
            raise ModelError('필수 열 누락: ' + ', '.join(sorted(missing)))
        if not rows:
            raise ModelError('도입 후 요구사항이 없다')
        ids = set()
        for header, records in [(hdr, rows), (shdr, srows)]:
            for row in records:
                value = row[header.index('ID')]
                if not value or value in ids:
                    raise ModelError('비어 있거나 중복된 ID: ' + value)
                ids.add(value)
        for row in rows:
            data = dict(zip(hdr, row))
            if data['상태'] not in STATES:
                raise ModelError('허용되지 않은 상태: ' + data['상태'])
            tests = items(data['테스트'])
            if len(tests) != len(set(tests)):
                raise ModelError('중복 테스트 연결: ' + data['ID'])
            cond = data['조건 수']
            if cond not in ('', '-', '—') and (not cond.isascii() or not cond.isdigit() or int(cond) < 1):
                raise ModelError('조건 수는 양의 정수 또는 —: ' + data['ID'])
            if not items(data['마일스톤']) and data['상태'] != '취소':
                raise ModelError('마일스톤이 없다: ' + data['ID'])
    return hdr, rows, shdr, srows


def markdown_table(header, rows):
    # Shell consumers split on pipes. Escape content pipes as entities first.
    def render(row):
        return '| ' + ' | '.join(v.replace('|', '&#124;') for v in row) + ' |'
    return '\n'.join([render(header), render(['---'] * len(header))] + [render(row) for row in rows])
