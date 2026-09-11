#!/usr/bin/env python3
"""Operational checks. Review statements remain claims, not machine proof of meaning."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import mdm_env
from mdm_model import read_map, visible_lines

CATALOG = 'docs/meta/requirements.json'
PENDING = 'docs/meta/sync-pending.json'
FRESHNESS = 'docs/meta/upstream.json'
IMPACTS = ('presentation', 'behavior', 'authorization', 'state', 'data', 'external')


def now():
    return datetime.now(timezone.utc).isoformat()


def require(E, condition, code, message):
    if not condition:
        E.error(code, message)


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def extracted(E, sources):
    require(E, isinstance(sources, list) and bool(sources), 'MDM_COVERAGE', '상류 추출 규칙이 필요하다')
    ids, files = {}, set()
    for src in sources:
        require(E, isinstance(src, dict) and set(src) == {'file', 'pattern'}, 'MDM_COVERAGE', 'source는 file/pattern')
        rel = src['file']
        require(E, isinstance(rel, str) and rel.startswith('docs/upstream/') and rel.endswith('.md') and rel not in files,
                'MDM_COVERAGE', '상류 Markdown 파일은 중복 없이 지정한다')
        files.add(rel)
        pattern = re.compile(src['pattern'])
        require(E, 'id' in pattern.groupindex and src['pattern'].startswith('^'), 'MDM_COVERAGE', '^로 시작하는 named group id 추출식이 필요하다')
        found = 0
        for line in visible_lines(E.path(rel).read_text(encoding='utf-8')):
            match = pattern.search(line)
            if match:
                ident = match.group('id')
                require(E, nonempty(ident) and ident not in ids, 'MDM_COVERAGE', '상류 ID가 비었거나 중복: ' + str(ident))
                ids[ident] = rel
                found += 1
        require(E, found > 0, 'MDM_COVERAGE', '요구사항 추출 0건: ' + rel)
    return ids


def coverage(E):
    obj = E.load(CATALOG)
    require(E, isinstance(obj, dict) and set(obj) == {'schema_version', 'sources', 'requirements'} and type(obj['schema_version']) is int and obj['schema_version'] == 1,
            'MDM_COVERAGE', '요구사항 목록 스키마 오류')
    ids = extracted(E, obj['sources'])
    decisions = obj['requirements']
    require(E, isinstance(decisions, dict) and set(ids) <= set(decisions), 'MDM_COVERAGE', '상류 ID와 처리 목록이 다르다: 추가·삭제를 검토한다')
    hdr, rows, _, _ = E.mapping()
    mapped = {r[hdr.index('ID')]: r[hdr.index('상태')] for r in rows}
    require(E, set(mapped) <= set(decisions), 'MDM_COVERAGE', '처리 목록에 없는 매핑 ID: ' + ', '.join(sorted(set(mapped) - set(decisions))))
    for ident, decision in decisions.items():
        require(E, isinstance(decision, dict) and set(decision) == {'disposition', 'reason', 'decision'} and decision['disposition'] in ('include', 'defer', 'exclude', 'retire'),
                'MDM_COVERAGE', '처리는 include/defer/exclude/retire: ' + ident)
        require(E, (ident in ids) == (decision['disposition'] != 'retire'), 'MDM_COVERAGE', '삭제 ID는 retire로 보존하며 재등장하면 재검토한다: ' + ident)
        if decision['disposition'] == 'include':
            require(E, ident in mapped and mapped[ident] != '취소', 'MDM_COVERAGE', '반영 요구사항 매핑 누락: ' + ident)
        else:
            require(E, nonempty(decision['reason']) and nonempty(decision['decision']), 'MDM_COVERAGE', '보류·제외 이유와 결정 근거 필요: ' + ident)
            allowed = ('취소',) if decision['disposition'] == 'retire' else ('⬜ 대기', '취소')
            require(E, ident not in mapped or mapped[ident] in allowed, 'MDM_COVERAGE', '보류·제외·삭제 요구사항이 활성 상태: ' + ident)
    return obj


def topics(story):
    return [x for x in story.get('impacts', ['behavior']) if x != 'presentation']


def comparison(E, matrix, story):
    required = topics(story)
    require(E, isinstance(matrix, list), 'MDM_SEMANTIC', '의미 비교는 행 목록이다')
    seen = set()
    for row in matrix:
        fields = {'topic', 'authority', 'consumer', 'actor', 'condition', 'action', 'result', 'resolution', 'reason'}
        require(E, isinstance(row, dict) and set(row) == fields and all(nonempty(v) for v in row.values()),
                'MDM_SEMANTIC', '비교 행의 정본·Story·역할·조건·행동·결과·판정 근거가 필요하다')
        require(E, row['topic'] in required and row['resolution'] in ('aligned', 'resolved'), 'MDM_SEMANTIC', '미해결 모순 또는 분류하지 않은 영향')
        for key in ('authority', 'consumer'):
            rel, sep, anchor = row[key].partition('#')
            require(E, sep and anchor, 'MDM_SEMANTIC', '비교 근거는 파일#실제 본문 조각')
            if rel == story['document'] and not E.path(rel, False).exists():
                rel = rel.replace('docs/plan/stories/', 'docs/plan/archive/stories/').replace('docs/plan/cycles/', 'docs/plan/archive/cycles/')
            require(E, anchor in E.path(rel).read_text(encoding='utf-8'), 'MDM_SEMANTIC', '인용 근거가 문서에 없다: ' + row[key])
        seen.add(row['topic'])
    require(E, seen == set(required), 'MDM_SEMANTIC', '영향별 비교가 빠졌다: ' + ', '.join(sorted(set(required) - seen)))


def work_snapshot(E):
    """Stable across commit/checkout; notes and generated receipts cannot hash themselves."""
    git = subprocess.run(['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=str(E.ROOT), capture_output=True)
    skip = {'.git', 'node_modules', 'vendor', 'dist', 'build', 'target', '.venv', 'venv', '__pycache__', '.pytest_cache', '.tmp'}
    if git.returncode == 0:
        names = sorted(set(os.fsdecode(v) for v in git.stdout.split(b'\0') if v))
    else:
        names = []
        for folder, dirs, files in os.walk(str(E.ROOT)):
            dirs[:] = [d for d in dirs if d not in skip]
            names += [(Path(folder) / f).relative_to(E.ROOT).as_posix() for f in files]
    result = {}
    for rel in names:
        if set(Path(rel).parts) & skip or rel.startswith(('docs/evidence/', 'docs/reports/')) or rel == 'docs/meta/.mdm-write.lock' or Path(rel).name.startswith('.env'):
            continue
        p = E.path(rel, False)
        if p.is_file():
            result[rel] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


def handoff_check(E):
    E.project()
    receipt = E.receipt('session', 'handoff')
    require(E, receipt and receipt.get('files') == work_snapshot(E), 'MDM_HANDOFF', '이번 변경에 대응하는 인계 기록이 없다. STATUS 갱신 후 mdm ops handoff 를 실행한다')
    return receipt


def references(E):
    # Kit instructions list optional upstream templates. Actual project references do not.
    docs = E.path('docs', False)
    files = list(docs.rglob('*.md')) + [E.path('CLAUDE.md', False)]
    for p in files:
        if not p.is_file() or any(x in p.parts for x in ('reports', 'evidence')):
            continue
        rel = p.relative_to(E.ROOT).as_posix()
        explanatory = rel.startswith('docs/guides/') or rel in ('docs/upstream/index.md', 'docs/index.md', 'docs/MOC.md', 'CLAUDE.md')
        for line in visible_lines(p.read_text(encoding='utf-8')):
            for target in re.findall(r'`((?:docs|\.claude)/[^`\s]+\.(?:md|sh|json|tsv))`', line):
                if any(x in target for x in ('<', '*', '…')):
                    continue
                if explanatory and target.startswith('docs/upstream/') and target.endswith('.md'):
                    continue
                require(E, E.path(target, False).exists(), 'MDM_REFERENCE', '깨진 참조: %s → %s' % (rel, target))


def sync_paths(E):
    directory = E.path('docs/upstream', False)
    return sorted([p.relative_to(E.ROOT).as_posix() for p in directory.glob('*') if p.is_file() and p.name != 'index.md' and (p.suffix == '.md' or p.name == 'manifest.tsv')] + [CATALOG, FRESHNESS, E.MAP])


def sync_target(E, rel):
    valid = rel in (CATALOG, FRESHNESS, E.MAP) or (rel.startswith('docs/upstream/') and len(Path(rel).parts) == 3 and Path(rel).name != 'index.md')
    require(E, valid, 'MDM_SYNC', '동기화 대상 경로 오류: ' + rel)
    return E.path(rel, False)


def sync_candidate(E, bundle_path):
    require(E, not E.path(PENDING, False).exists(), 'MDM_SYNC_PENDING', '미완료 동기화는 sync-recover로 복구한다')
    bundle = E.load(bundle_path)
    require(E, isinstance(bundle, dict) and set(bundle) in ({'schema_version', 'files', 'catalog'}, {'schema_version', 'files', 'catalog', 'mapping'}) and type(bundle['schema_version']) is int and bundle['schema_version'] == 1 and isinstance(bundle['files'], list) and bool(bundle['files']), 'MDM_SYNC', '동기화 묶음 형식 오류')
    content, entries = {}, []
    for item in bundle['files']:
        require(E, isinstance(item, dict) and set(item) == {'file', 'source', 'input'} and nonempty(item['source']) and not any(c in item['source'] for c in '\t\r\n'), 'MDM_SYNC', 'file/source/input이 필요하다')
        name = item['file']
        require(E, isinstance(name, str) and Path(name).name == name and name.endswith('.md') and name != 'index.md', 'MDM_SYNC', '단일 Markdown 파일명만 허용한다')
        rel = 'docs/upstream/' + name
        require(E, rel not in content, 'MDM_SYNC', '중복 대상 파일')
        content[rel] = E.path(item['input']).read_bytes()
        entries.append((name, item['source'], hashlib.sha256(content[rel]).hexdigest()))
    content[CATALOG] = E.packed(bundle['catalog']) + b'\n'
    content[E.MAP] = E.path(bundle.get('mapping', E.MAP)).read_bytes()
    # Validate candidate requirements against the current mapping before changing any live file.
    original_root = E.ROOT
    with tempfile.TemporaryDirectory(prefix='mdm-sync-check-') as tmp:
        shadow = Path(tmp)
        (shadow / 'docs/spec').mkdir(parents=True)
        shutil.copy2(E.path(E.MAP), shadow / E.MAP)
        for rel, value in content.items():
            target = shadow / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)
        try:
            E.ROOT = shadow
            coverage(E)
        finally:
            E.ROOT = original_root
    old = {rel: hashlib.sha256(E.path(rel).read_bytes()).hexdigest() if E.path(rel, False).exists() else None for rel in sync_paths(E)}
    basis = E.digest({'old': old, 'new': {k: hashlib.sha256(v).hexdigest() for k, v in content.items()}, 'entries': entries})
    return content, entries, basis


def recover(E):
    journal = E.load(PENDING)
    require(E, isinstance(journal, dict) and journal.get('schema_version') == 1 and isinstance(journal.get('before'), dict), 'MDM_SYNC', '복구 기록 형식 오류')
    # Validate every path and value before the first write.
    restored = {}
    for rel, value in journal['before'].items():
        sync_target(E, rel)
        restored[rel] = base64.b64decode(value, validate=True) if value is not None else None
    for rel, value in restored.items():
        if value is None:
            target = sync_target(E, rel)
            if target.exists():
                target.unlink()
        else:
            E.atomic_bytes(rel, value)
    E.path(PENDING).unlink()


def plan(E, sid):
    story = E.registry()['stories'][sid]
    read = [story['document'], 'docs/spec/source-map.md']
    required = topics(story)
    if required:
        read += story['inputs']
    if set(required) & {'authorization', 'state', 'data'}:
        read += ['docs/spec/domain.md', 'docs/spec/product.md']
    if 'external' in required:
        read += ['docs/spec/interface.md', 'docs/spec/stack.md']
    return {'story': sid, 'impacts': story.get('impacts', ['behavior']), 'read': list(dict.fromkeys(read)),
            'compare_topics': required, 'checks': ['current readiness', 'project tests', 'consistency', 'handoff at close'],
            'rule': '영향 없음인 문서는 수정하지 않는다. 미결정 영향은 behavior 이상으로 분류한다.'}


def ci_pin(E):
    """제품 CI 양식(.github/workflows/mdm-check.yml)이 고정한 dev-kit 버전(MDM_KIT_REF). 파일·핀이 없으면 None."""
    p = E.path('.github/workflows/mdm-check.yml', False)
    if not p.is_file():
        return None
    m = re.search(r'MDM_KIT_REF:\s*["\']?v?([0-9][\w.\-]*)', p.read_text(encoding='utf-8'))
    return m.group(1) if m else None


def doctor(E, repo, branch, run=False):
    scripts = ['mdm-contract.py', 'mdm_model.py', 'mdm_operations.py', 'mdm-ops.py', 'mdm-check.sh', 'check-consistency.sh', 'check-plan.py']
    version = mdm_env.plugin_version()
    pin = ci_pin(E)
    ci = E.path('.github/workflows/mdm-check.yml', False)
    ci_text = ci.read_text(encoding='utf-8') if ci.is_file() else None
    # 엔진은 플러그인에 있다. 제품 CI 는 원본 저장소를 MDM_KIT_REF 로 받아 오므로, 그 핀이 지금 쓰는 플러그인
    # 버전과 다르면 로컬과 CI 가 다른 엔진으로 판정한다 — 둘을 대조해 보고한다 (비교 불가면 None).
    result = {'runtime': 'python3', 'engine': str(mdm_env.ENGINE), 'plugin_version': version,
              'scripts': {n: (mdm_env.ENGINE / n).is_file() for n in scripts},
              'adopted': False,
              'ci_file': E.path('.github/workflows/mdm-check.yml', False).is_file(),
              'ci_pin': pin,
              # 파일이 없거나 플러그인 버전을 모르면 판단 불가(None). 파일은 있는데 핀이 없으면 1.x 양식이거나
              # 직접 쓴 CI 라 플러그인과 같은 엔진을 받는다는 보장이 없다(False) — issues #427.
              'ci_pin_matches': None if (ci_text is None or not version) else (pin == version),
              # 옛 엔진 경로를 부르는 CI — --retire-legacy 로 옛 파일을 물리면 그 순간 깨진다.
              'ci_legacy': bool(ci_text) and '.claude/scripts/' in ci_text,
              'local_check': {'status': 'not run'},
              'remote': {'status': 'unknown', 'reason': 'not queried'}}
    try:
        E.project(); coverage(E); E.registry()
        result['adopted'] = True
    except (OSError, ValueError, TypeError, KeyError) as exc:
        result['configuration_error'] = str(exc)
    if run:
        env = dict(os.environ, MDM_PROJECT_ROOT=str(E.ROOT))
        p = subprocess.run(['bash', str(mdm_env.ENGINE / 'mdm-check.sh')], cwd=str(E.ROOT), env=env, capture_output=True, text=True)
        result['local_check'] = {'status': 'passed' if p.returncode == 0 else 'failed', 'returncode': p.returncode, 'output': p.stdout + p.stderr}
    if repo:
        require(E, re.fullmatch(r'[\w.-]+/[\w.-]+', repo), 'MDM_DOCTOR', 'GitHub 저장소는 owner/repo')
        from urllib.parse import quote
        def api(endpoint):
            p = subprocess.run(['gh', 'api', endpoint], cwd=str(E.ROOT), capture_output=True, text=True)
            if p.returncode:
                raise ValueError(p.stderr.strip() or 'GitHub 조회 실패')
            return json.loads(p.stdout)
        try:
            head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=str(E.ROOT), text=True).strip()
            workflow = api('repos/%s/actions/workflows/mdm-check.yml' % repo)
            protection = api('repos/%s/branches/%s/protection/required_status_checks' % (repo, quote(branch, safe='')))
            checks = api('repos/%s/commits/%s/check-runs?per_page=100' % (repo, head))
            contexts = set(protection.get('contexts', [])) | {c['context'] for c in protection.get('checks', [])}
            result['remote'] = {'status': 'queried', 'workflow_active': workflow.get('state') == 'active',
                'required_on_branch': 'mdm-check' in contexts, 'branch': branch, 'sha': head,
                'head_success_observed': any(c.get('name') == 'mdm-check' and c.get('conclusion') == 'success' for c in checks.get('check_runs', [])),
                'scope': 'classic branch protection; rulesets and other branches not evaluated'}
        except (OSError, ValueError, subprocess.SubprocessError) as exc:
            result['remote'] = {'status': 'unknown', 'reason': str(exc)}
    return result


def pilot(E, obj):
    metrics = ('contradictions_before', 'drift_after', 'rework_minutes', 'questions', 'necessary_questions',
               'documents_read', 'review_candidates', 'affected_candidates', 'false_alarms', 'check_seconds', 'handoff_errors')
    require(E, isinstance(obj, dict) and set(obj) == set(metrics) | {'kind', 'project', 'change', 'evidence'} and obj['kind'] in ('actual', 'rehearsal') and nonempty(obj['project']) and nonempty(obj['change']) and isinstance(obj['evidence'], list) and bool(obj['evidence']) and all(nonempty(v) for v in obj['evidence']), 'MDM_PILOT', '실전/리허설 구분과 측정 근거가 필요하다')
    require(E, all(type(obj[k]) in (int, float) and obj[k] >= 0 and obj[k] < float('inf') for k in metrics), 'MDM_PILOT', '측정값은 음수가 아닌 유한수')
    require(E, obj['necessary_questions'] <= obj['questions'] and obj['affected_candidates'] <= obj['review_candidates'], 'MDM_PILOT', '부분 건수가 전체보다 크다')
    return dict(obj, question_precision=obj['necessary_questions'] / obj['questions'] if obj['questions'] else None,
                impact_precision=obj['affected_candidates'] / obj['review_candidates'] if obj['review_candidates'] else None)


def main(E, argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    cat = sub.add_parser('catalog')
    cat.add_argument('--source', action='append', required=True)
    cat.add_argument('--pattern', required=True)
    work = sub.add_parser('plan'); work.add_argument('story')
    hand = sub.add_parser('handoff'); hand.add_argument('--note', required=True)
    sub.add_parser('handoff-check')
    sub.add_parser('refs')
    for action in ('sync-preview', 'sync-apply'):
        sync = sub.add_parser(action); sync.add_argument('--bundle', required=True)
        if action == 'sync-apply':
            sync.add_argument('--basis', required=True)
    sub.add_parser('sync-recover')
    fresh = sub.add_parser('freshness'); fresh.add_argument('--failed')
    diag = sub.add_parser('doctor'); diag.add_argument('--github'); diag.add_argument('--branch', default='main'); diag.add_argument('--run', action='store_true')
    run = sub.add_parser('pilot'); run.add_argument('--record', required=True)
    args = parser.parse_args(argv)
    try:
        result = None
        if args.action == 'catalog':
            sources = [{'file': p, 'pattern': args.pattern} for p in args.source]
            result = {'schema_version': 1, 'sources': sources, 'requirements': {key: {'disposition': 'include', 'reason': '', 'decision': ''} for key in extracted(E, sources)}}
        elif args.action == 'plan':
            E.project(); result = plan(E, args.story)
        elif args.action == 'handoff':
            E.project()
            with E.write_lock():
                obj = E.load(args.note)
                fields = {'done', 'pending', 'decisions', 'next', 'blockers'}
                require(E, isinstance(obj, dict) and set(obj) == fields and all(isinstance(v, list) and all(nonempty(x) for x in v) for v in obj.values()) and bool(obj['next']), 'MDM_HANDOFF', '완료·미완료·결정·다음 행동·막힘의 5칸이 필요하다')
                result = {'receipt': E.record('session', 'handoff', {'note': obj, 'files': work_snapshot(E)})}
        elif args.action == 'handoff-check':
            result = {'status': 'current', 'note': handoff_check(E)['note']}
        elif args.action == 'refs':
            references(E); result = {'references': 'passed'}
        elif args.action == 'sync-preview':
            content, entries, basis = sync_candidate(E, args.bundle)
            result = {'basis': basis, 'write': sorted(content), 'remove': sorted(set(sync_paths(E)) - set(content) - {FRESHNESS, 'docs/upstream/manifest.tsv'}),
                      'sources': [e[1] for e in entries], 'review': '검토할 스냅샷·목록 전체. 의미·소유권 이동은 사람이 판정한다.'}
        elif args.action == 'sync-apply':
            with E.write_lock():
                content, entries, basis = sync_candidate(E, args.bundle)
                require(E, basis == args.basis, 'MDM_SYNC', '검토한 묶음 또는 현재 파일이 달라졌다. preview부터 다시 실행한다')
                stamp = now()
                content['docs/upstream/manifest.tsv'] = ''.join('%s\t%s\t%s\t%s\n' % (name, source, stamp, sha) for name, source, sha in entries).encode()
                content[FRESHNESS] = E.packed({'status': 'confirmed_at', 'last_attempt': stamp, 'last_success': stamp, 'reason': '', 'sources': [e[1] for e in entries]}) + b'\n'
                targets = set(sync_paths(E)) | set(content)
                before = {rel: base64.b64encode(sync_target(E, rel).read_bytes()).decode() if sync_target(E, rel).exists() else None for rel in targets}
                E.atomic_json(PENDING, {'schema_version': 1, 'before': before}, True)
                try:
                    for rel in sorted(targets):
                        if rel in content:
                            E.atomic_bytes(rel, content[rel])
                        elif sync_target(E, rel).exists():
                            sync_target(E, rel).unlink()
                    E.path(PENDING).unlink()
                except BaseException:
                    recover(E)
                    raise
                result = {'status': 'applied', 'last_success': stamp, 'next': '소유권·의미 변경 검토 후 ready/verify'}
        elif args.action == 'sync-recover':
            with E.write_lock():
                recover(E)
            result = {'status': 'restored'}
        elif args.action == 'freshness':
            result = E.load(FRESHNESS) if E.path(FRESHNESS, False).exists() else {'status': 'unknown', 'last_attempt': None, 'last_success': None, 'reason': 'not collected'}
            if args.failed:
                with E.write_lock():
                    result.update(status='failed', last_attempt=now(), reason=args.failed)
                    E.atomic_json(FRESHNESS, result)
        elif args.action == 'doctor':
            result = doctor(E, args.github, args.branch, args.run)
        elif args.action == 'pilot':
            result = pilot(E, E.load(args.record))
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, TypeError, KeyError, re.error) as exc:
        print('실패  ' + str(exc))
        return 1
