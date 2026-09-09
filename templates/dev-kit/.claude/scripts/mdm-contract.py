#!/usr/bin/env python3
"""File-level contract evidence. Uses only the Python standard library.

Checks never rewrite evidence. Receipts record a reviewed input fingerprint;
they are not signatures or proof that a human review really occurred.
JUnit reports are supplied by the project's test runner, not inferred by grep.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from mdm_model import ACTIVE, ModelError, items, markdown_table, read_map, section_table
import mdm_operations as operations

ROOT = Path(__file__).resolve().parents[2]
PROJECT = 'docs/meta/project.json'
REGISTRY = 'docs/meta/stories.json'
MAP = 'docs/spec/source-map.md'
SLOTS = ('state', 'authorization', 'rules', 'data', 'exceptions', 'presentation',
         'checks', 'preconditions', 'trigger', 'action', 'result', 'acceptance')


def error(code, message):
    raise ModelError(code + ' — ' + message)


def packed(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')


def digest(obj):
    return hashlib.sha256(packed(obj)).hexdigest()


def path(rel, must_exist=True):
    p = Path(rel)
    if p.is_absolute() or '..' in p.parts or not p.parts:
        error('MDM_PATH', '프로젝트 상대 경로만 허용: ' + str(rel))
    out = ROOT / p
    # Reject symlinks, including output parents. Hashing must not escape the repo.
    for candidate in [out] + list(out.parents):
        if candidate == ROOT:
            break
        if candidate.is_symlink():
            error('MDM_PATH', '심볼릭 링크는 입력·기록 경로로 쓰지 않는다: ' + str(rel))
    if must_exist and not out.is_file():
        error('MDM_MISSING', '파일이 없다: ' + str(rel))
    return out


def load(rel):
    def unique(pairs):
        obj = {}
        for key, value in pairs:
            if key in obj:
                error('MDM_SCHEMA', '중복 JSON 키: ' + key)
            obj[key] = value
        return obj
    return json.loads(path(rel).read_text(encoding='utf-8'), object_pairs_hook=unique)


def atomic_bytes(rel, content, exclusive=False):
    target = path(rel, False)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.mdm-', dir=str(target.parent))
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        if exclusive:
            os.link(name, str(target))  # Atomic publication without overwriting history.
        else:
            os.replace(name, str(target))
    finally:
        if os.path.exists(name):
            os.unlink(name)


def atomic_json(rel, obj, exclusive=False):
    atomic_bytes(rel, packed(obj) + b'\n', exclusive)

@contextmanager
def write_lock():
    lock = path('docs/meta/.mdm-write.lock', False)
    lock.parent.mkdir(parents=True, exist_ok=True)
    try:
        lock.mkdir()
    except FileExistsError:
        error('MDM_BUSY', '다른 기록 작업 중이다. 중단된 작업이면 잠금 디렉터리를 확인한다')
    try:
        yield
    finally:
        lock.rmdir()


def project():
    if path(operations.PENDING, False).exists():
        error('MDM_SYNC_PENDING', '미완료 동기화가 있다. mdm-ops.py sync-recover로 복구한다')
    obj = load(PROJECT)
    if not isinstance(obj, dict) or type(obj.get('schema_version')) is not int or set(obj) != {'schema_version', 'lifecycle'} or obj != {
            'schema_version': 1, 'lifecycle': 'adopted'}:
        error('MDM_SCHEMA', '지원하지 않는 도입 상태/스키마. adopt로 명시적으로 도입한다')
    return obj


def mapping(strict=True):
    try:
        return read_map(path(MAP).read_text(encoding='utf-8'), strict)
    except ModelError as e:
        error('MDM_SCHEMA', str(e))


def validate_registry(obj):
    if not isinstance(obj, dict) or set(obj) != {'schema_version', 'stories'} or type(obj['schema_version']) is not int or obj['schema_version'] != 1 or not isinstance(obj['stories'], dict):
        error('MDM_SCHEMA', 'stories.json 형식 오류')
    hdr, rows, _, _ = mapping()
    known = {r[hdr.index('ID')] for r in rows}
    for sid, story in obj['stories'].items():
        if not re.fullmatch(r'ST-[0-9]+', sid) or not isinstance(story, dict) or set(story) not in ({'requirements', 'document', 'inputs', 'criteria'}, {'requirements', 'document', 'inputs', 'criteria', 'impacts'}):
            error('MDM_SCHEMA', 'Story ID 또는 필드 오류: ' + sid)
        impacts = story.get('impacts', ['behavior'])
        if not isinstance(impacts, list) or not impacts or not all(isinstance(v, str) and v in operations.IMPACTS for v in impacts) or len(impacts) != len(set(impacts)):
            error('MDM_SCHEMA', 'Story 영향 분류 오류: ' + sid)
        for field in ('requirements', 'inputs'):
            values = story[field]
            if not isinstance(values, list) or not values or not all(isinstance(v, str) and v for v in values) or len(values) != len(set(values)):
                error('MDM_SCHEMA', 'Story 목록 오류: ' + sid + '/' + field)
        if not set(story['requirements']) <= known:
            error('MDM_SCHEMA', '없는 요구사항을 인용: ' + sid)
        if not isinstance(story['document'], str) or not story['document'].endswith('.md'):
            error('MDM_SCHEMA', 'Story의 계약 문서가 필요하다: ' + sid)
        criteria = story['criteria']
        if not isinstance(criteria, dict):
            error('MDM_SCHEMA', '수용 기준 연결 형식 오류: ' + sid)
        for criterion, tests in criteria.items():
            if '/' not in criterion or criterion.rsplit('/', 1)[0] not in story['requirements'] or not criterion.rsplit('/', 1)[1]:
                error('MDM_SCHEMA', '수용 기준은 요구사항ID/기준ID: ' + criterion)
            if not isinstance(tests, list) or not tests or not all(isinstance(t, str) and '::' in t for t in tests) or len(set(tests)) != len(tests):
                error('MDM_SCHEMA', '테스트는 중복 없는 classname::name 목록: ' + criterion)
    return obj


def registry():
    return validate_registry(load(REGISTRY))


def story_inputs(sid, data=None):
    data = data or registry()
    if sid not in data['stories']:
        error('MDM_SCHEMA', '등록되지 않은 Story: ' + sid)
    story = data['stories'][sid]
    doc = story['document']
    if not path(doc, False).is_file():
        # Archive is a physical relocation; the logical document identity stays fixed.
        doc = doc.replace('docs/plan/stories/', 'docs/plan/archive/stories/').replace('docs/plan/cycles/', 'docs/plan/archive/cycles/')
    document = hashlib.sha256(path(doc).read_bytes()).hexdigest()
    selected = set(story['inputs'])
    # Conservative v1 baseline: all existing spec contracts and collected snapshots.
    for folder in ('docs/spec', 'docs/upstream'):
        directory = path(folder, False)
        if directory.is_dir():
            for p in directory.glob('*.md'):
                if p.name not in ('index.md', 'source-map.md'):
                    selected.add(p.relative_to(ROOT).as_posix())
    if path('docs/upstream/manifest.tsv', False).exists():
        selected.add('docs/upstream/manifest.tsv')
    files = {}
    for rel in sorted(selected):
        if rel.startswith(('docs/evidence/', 'docs/reports/', 'docs/meta/')) or rel == MAP:
            error('MDM_SCHEMA', '계산 결과·레지스트리를 계약 입력으로 쓰면 순환한다: ' + rel)
        files[rel] = hashlib.sha256(path(rel).read_bytes()).hexdigest()
    hdr, rows, _, _ = mapping()
    # Workflow status/ready/tests/cycle are outputs, not contract content.
    contracts = [{k: dict(zip(hdr, row))[k] for k in ('ID', '출처', '화면', '조건 수')}
                 for row in rows if row[hdr.index('ID')] in story['requirements']]
    return {'schema_version': 1, 'story': sid, 'definition': story,
            'coverage': operations.coverage(sys.modules[__name__]),
            'document': document, 'files': files, 'requirements': sorted(contracts, key=lambda r: r['ID']),
            'policy': {name: hashlib.sha256(path('.claude/scripts/' + name).read_bytes()).hexdigest()
                       for name in ('mdm-contract.py', 'mdm_model.py', 'mdm_operations.py')}}


def receipt(sid, kind):
    directory = path('docs/evidence/%s/%s' % (kind, sid), False)
    if not directory.exists():
        return None
    files = sorted(directory.glob('*.json'))
    if not files:
        return None
    obj = load(files[-1].relative_to(ROOT).as_posix())
    if not isinstance(obj, dict) or obj.get('story') != sid or obj.get('kind') != kind or obj.get('schema_version') != 1:
        error('MDM_SCHEMA', '판정 기록 형식 오류: ' + sid)
    return obj


def record(sid, kind, body):
    directory = path('docs/evidence/%s/%s' % (kind, sid), False)
    directory.mkdir(parents=True, exist_ok=True)
    nums = [int(p.stem) for p in directory.glob('*.json') if p.stem.isdigit()]
    rel = 'docs/evidence/%s/%s/%012d.json' % (kind, sid, max(nums or [0]) + 1)
    obj = dict(body, schema_version=1, story=sid, kind=kind,
               created_at=datetime.now(timezone.utc).isoformat())
    atomic_json(rel, obj, exclusive=True)
    return rel


def readiness(sid, data):
    inputs = story_inputs(sid, data)
    old = receipt(sid, 'readiness')
    if not old:
        return False, '미검증'
    if old.get('fingerprint') != digest(inputs) or old.get('inputs') != inputs:
        return False, '재검토 필요: 계약 또는 의존 관계 변경'
    validate_assessment(old.get('assessment'))
    operations.comparison(sys.modules[__name__], old.get('comparison'), data['stories'][sid])
    if not isinstance(old.get('reviewed_by'), str) or not old['reviewed_by'].strip():
        error('MDM_SCHEMA', '판정 주체가 없다: ' + sid)
    return True, '유효'


def validate_assessment(obj):
    if not isinstance(obj, dict) or set(obj) != set(SLOTS):
        error('MDM_ASSESSMENT', '12개 슬롯을 전부 판정해야 한다')
    for slot, entry in obj.items():
        if not isinstance(entry, dict) or set(entry) != {'status', 'evidence'} or entry['status'] not in ('answered', 'not_applicable') or not isinstance(entry['evidence'], str) or not entry['evidence'].strip():
            error('MDM_ASSESSMENT', slot + ': 답의 근거 또는 해당 없음의 이유가 필요하다')


def code_inputs():
    skip = {'.git', '.claude', 'docs', 'node_modules', 'vendor', 'dist', 'build', 'target', '.venv', 'venv', '__pycache__', '.pytest_cache', '.tmp'}
    result = {}
    git = subprocess.run(['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=str(ROOT), capture_output=True)
    if git.returncode == 0:
        names = sorted(set(os.fsdecode(x) for x in git.stdout.split(b'\0') if x))
    else:
        names = []
        for directory, dirs, files in os.walk(str(ROOT)):
            dirs[:] = [d for d in dirs if d not in skip]
            names.extend((Path(directory) / name).relative_to(ROOT).as_posix() for name in files)
    for name in sorted(names):
        if set(Path(name).parts) & skip or name.endswith('.md') or Path(name).name.startswith('.env'):
            continue
        p = path(name, False)
        if p.is_file():
            result[name] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


def test_results(output):
    root = ET.parse(output).getroot()
    if root.tag not in ('testsuite', 'testsuites'):
        error('MDM_VERIFICATION', 'JUnit testsuite/testsuites가 아니다')
    results = {}
    for case in root.iter('testcase'):
        name = case.get('classname', '') + '::' + case.get('name', '')
        if not case.get('classname') or not case.get('name') or name in results:
            error('MDM_VERIFICATION', 'JUnit 테스트 식별자가 없거나 중복: ' + name)
        results[name] = 'failed' if case.find('failure') is not None or case.find('error') is not None else 'skipped' if case.find('skipped') is not None else 'passed'
    if not results or any(x != 'passed' for x in results.values()):
        error('MDM_VERIFICATION', '미실행·실패·skip 테스트가 있다')
    return results


def criteria_covered(story, results):
    return bool(story['criteria']) and all(results.get(t) == 'passed' for tests in story['criteria'].values() for t in tests)


def verification(sid, data):
    old = receipt(sid, 'verification')
    if not old or old.get('contract') != digest(story_inputs(sid, data)) or old.get('files') != code_inputs():
        return False
    return old.get('returncode') == 0 and criteria_covered(data['stories'][sid], old.get('results', {}))


def evaluated(scope=None):
    project()
    operations.coverage(sys.modules[__name__])
    data = registry()
    hdr, rows, shdr, srows = mapping()
    errors = []
    info = {}
    for sid in data['stories']:
        ok, reason = readiness(sid, data)
        info[sid] = {'valid': ok, 'reason': reason}
    if scope and scope not in info:
        error('MDM_SCHEMA', '알 수 없는 검사 범위: ' + scope)
    for row in rows:
        req = dict(zip(hdr, row))
        children = [sid for sid, story in data['stories'].items() if req['ID'] in story['requirements']]
        row[hdr.index('테스트')] = ', '.join(sorted({t.split('::')[-1] for sid in children for tests in data['stories'][sid]['criteria'].values() for t in tests})) or '—'
        valid = bool(children) and all(info[s]['valid'] for s in children)
        row[hdr.index('준비')] = ('✅ ' if valid else '❌ 재판정 ') + (','.join(children) or 'Story 미등록')
        selected = not scope or scope in children
        if selected and req['상태'] in ACTIVE and not valid:
            errors.append('MDM_STALE — %s: %s' % (req['ID'], '; '.join(s + ': ' + info[s]['reason'] for s in children) or 'Story 미등록'))
        if selected and req['상태'] == '✅ 완료':
            criteria = {c for sid in children for c in data['stories'][sid]['criteria'] if c.startswith(req['ID'] + '/')}
            count = req['조건 수']
            if not criteria or (count.isdigit() and len(criteria) != int(count)) or not all(verification(s, data) for s in children):
                errors.append('MDM_VERIFICATION — %s: 현재 수용 기준·코드의 실행 증거가 부족하거나 낡았다' % req['ID'])
    return hdr, rows, shdr, srows, info, errors


def snapshot(args):
    if args.initializing:
        if path(PROJECT, False).exists():
            error('MDM_SCHEMA', '도입 후 --init으로 운영 검사를 끌 수 없다')
        if path(MAP, False).exists():
            hdr, rows, shdr, srows = mapping(False)
        else:
            hdr, rows, shdr, srows = [], [], [], []
        # This mode exists only for plan/adoption preparation, never completion.
        print('경고  MDM_INIT — 초기화 검사이며 운영 통과가 아니다')
    else:
        hdr, rows, shdr, srows, _, errors = evaluated(args.scope)
        if errors:
            error('MDM_CHECK', '\n'.join(errors))
    if args.output:
        out = '# source-map\n\n## 2. 요구사항 매핑표\n\n' + (markdown_table(hdr, rows) if hdr else '')
        out += '\n\n## 3. 화면 매핑표\n\n' + (markdown_table(shdr, srows) if shdr else '') + '\n'
        Path(args.output).write_text(out, encoding='utf-8')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('render', help='계산된 준비 상태를 source-map 표에 반영 (검사 통과 명령 아님)')
    sub.add_parser('adopt', help='기존 매핑을 검증하고 운영 상태를 생성 (재실행은 보존)')
    reg = sub.add_parser('register')
    reg.add_argument('story')
    reg.add_argument('--requirement', action='append', required=True)
    reg.add_argument('--document', required=True)
    reg.add_argument('--input', action='append', required=True)
    reg.add_argument('--criterion', action='append', default=[], help='REQ/AC=classname::test (여러 번 가능)')
    reg.add_argument('--impact', action='append', choices=operations.IMPACTS, help='생략하면 behavior. 여러 영향은 반복 지정')
    inspect = sub.add_parser('inspect')
    inspect.add_argument('story')
    ready = sub.add_parser('ready')
    ready.add_argument('story')
    ready.add_argument('--basis', required=True)
    ready.add_argument('--assessment', required=True)
    ready.add_argument('--reviewed-by', required=True)
    ready.add_argument('--comparison', help='영향별 의미 비교 JSON. presentation만이면 생략 가능')
    verify = sub.add_parser('verify')
    verify.add_argument('story')
    verify.add_argument('command', nargs=argparse.REMAINDER)
    check = sub.add_parser('check')
    check.add_argument('--scope')
    check.add_argument('--init', dest='initializing', action='store_true')
    check.add_argument('--output', help='shell bridge output (temporary file)')
    args = parser.parse_args()
    try:
        if args.action == 'check':
            return snapshot(args)
        if args.action == 'render':
            with write_lock():
                hdr, rows, shdr, srows, _, errors = evaluated()
                original = path(MAP).read_text(encoding='utf-8')
                for num, header, records in [(2, hdr, rows), (3, shdr, srows)]:
                    _, _, (start, end) = section_table(original, num, strict=True, with_span=True)
                    lines = original.splitlines(keepends=True)
                    original = ''.join(lines[:start]) + markdown_table(header, records) + '\n' + ''.join(lines[end:])
                atomic_bytes(MAP, original.encode('utf-8'))
                print('source-map 표시 갱신. 운영 검사는 check로 실행한다.')
                for message in errors:
                    print('경고  ' + message)
            return 0
        if args.action == 'adopt':
            mapping()
            operations.coverage(sys.modules[__name__])
            with write_lock():
                if path(PROJECT, False).exists():
                    project()
                    registry()
                else:
                    if path(REGISTRY, False).exists():
                        registry()
                    else:
                        atomic_json(REGISTRY, {'schema_version': 1, 'stories': {}}, True)
                    atomic_json(PROJECT, {'schema_version': 1, 'lifecycle': 'adopted'}, True)
            print('도입 상태 등록. 기존 ✅는 승계하지 않는다 — register → inspect → ready 순서로 판정한다')
            return 0
        project()
        if args.action == 'register':
            with write_lock():
                data = registry()
                criteria = {}
                for value in args.criterion:
                    if '=' not in value:
                        error('MDM_SCHEMA', '--criterion은 REQ/AC=classname::test')
                    key, test = value.split('=', 1)
                    criteria.setdefault(key, []).append(test)
                story = {'requirements': args.requirement, 'document': args.document, 'inputs': args.input, 'criteria': criteria, 'impacts': args.impact or ['behavior']}
                previous = data['stories'].get(args.story)
                if previous is not None and previous != story:
                    error('MDM_SCHEMA', '이미 등록된 Story다. 의존 변경은 stories.json diff로 검토한다; 과거 기록은 보존한다')
                data['stories'][args.story] = story
                # Validate before publishing by checking inputs and basic shape here.
                if not re.fullmatch(r'ST-[0-9]+', args.story):
                    error('MDM_SCHEMA', 'Story ID는 ST-숫자')
                hdr, rows, _, _ = mapping()
                if not set(args.requirement) <= {r[hdr.index('ID')] for r in rows}:
                    error('MDM_SCHEMA', '매핑에 없는 요구사항')
                validate_registry(data)
                story_inputs(args.story, data)
                atomic_json(REGISTRY, data)
            print('Story 등록: ' + args.story)
        elif args.action == 'inspect':
            inputs = story_inputs(args.story)
            print(json.dumps({'fingerprint': digest(inputs), 'inputs': inputs}, ensure_ascii=False, indent=2))
        elif args.action == 'ready':
            with write_lock():
                data = registry()
                before = story_inputs(args.story, data)
                if digest(before) != args.basis:
                    error('MDM_STALE', '검토 시작 때의 입력과 달라졌다. inspect 후 다시 검토한다')
                assessment = load(args.assessment)
                validate_assessment(assessment)
                matrix = load(args.comparison) if args.comparison else []
                operations.comparison(sys.modules[__name__], matrix, data['stories'][args.story])
                if not args.reviewed_by.strip():
                    error('MDM_ASSESSMENT', '판정 주체가 필요하다')
                if before != story_inputs(args.story):
                    error('MDM_STALE', '판정 중 계약이 변경됐다')
                print(record(args.story, 'readiness', {'inputs': before, 'fingerprint': digest(before),
                      'assessment': assessment, 'comparison': matrix, 'reviewed_by': args.reviewed_by}))
        elif args.action == 'verify':
            cmd = args.command[1:] if args.command[:1] == ['--'] else args.command
            if not cmd:
                error('MDM_VERIFICATION', '-- 뒤에 실행 명령이 필요하다')
            with write_lock():
                data = registry()
                if not readiness(args.story, data)[0]:
                    error('MDM_STALE', '현재 계약의 준비 판정이 먼저 필요하다')
                contract = digest(story_inputs(args.story, data))
                files = code_inputs()
                try:
                    with tempfile.TemporaryDirectory(prefix='mdm-junit-') as directory:
                        output = Path(directory) / 'results.xml'
                        env = os.environ.copy()
                        env['MDM_JUNIT_OUTPUT'] = str(output)
                        proc = subprocess.run(cmd, cwd=str(ROOT), env=env)
                        if proc.returncode != 0 or not output.is_file():
                            error('MDM_VERIFICATION', '명령 실패 또는 JUnit 보고서 미생성 (MDM_JUNIT_OUTPUT)')
                        results = test_results(output)
                        if not criteria_covered(data['stories'][args.story], results):
                            error('MDM_VERIFICATION', '등록된 수용 기준을 실행 결과가 덮지 못했다')
                        if contract != digest(story_inputs(args.story)) or files != code_inputs():
                            error('MDM_VERIFICATION', '실행 중 입력이 변경됐다 — 다시 실행한다')
                        print(record(args.story, 'verification', {'contract': contract, 'files': files,
                              'command': cmd, 'returncode': proc.returncode, 'results': results,
                              'report_sha256': hashlib.sha256(output.read_bytes()).hexdigest()}))
                except (ModelError, OSError, ValueError, ET.ParseError) as exc:
                    record(args.story, 'verification', {'contract': contract, 'files': files,
                           'command': cmd, 'returncode': 1, 'results': {}, 'error': str(exc)})
                    raise

        return 0
    except (ModelError, OSError, ValueError, TypeError, KeyError, ET.ParseError) as exc:
        print('실패  ' + str(exc))
        return 1


if __name__ == '__main__':
    sys.exit(main())
