"""Operational gaps: omissions, semantic review, handoff, sync, deployment."""
import json
from pathlib import Path
import subprocess
import sys
import test_contracts as fixtures
KIT = fixtures.KIT


class Operations(fixtures.Contracts):
    # Inherit fixture helpers, not the base regression cases.
    def ops(self, *args, rc=0):
        p = subprocess.run([sys.executable, str(self.root / '.claude/scripts/mdm-ops.py'), *args],
                           cwd=self.root, text=True, capture_output=True)
        self.assertEqual(p.returncode, rc, p.stdout + p.stderr)
        return p.stdout

    def catalog(self):
        self.put('docs/upstream/prd.md', '# PRD\n## FR-1 Delete\n## FR-2 Restore\n')
        obj = json.loads(self.ops('catalog', '--source', 'docs/upstream/prd.md',
                                 '--pattern', r'^## (?P<id>FR-\d+)\b'))
        self.put('docs/meta/requirements.json', json.dumps(obj))
        return obj

    def test_unmapped_upstream_requirement_fails(self):
        self.catalog()
        self.assertIn('MDM_COVERAGE', self.cli('adopt', rc=1))

    def test_exclusion_requires_reason_and_decision(self):
        obj = self.catalog()
        obj['requirements']['FR-2'] = {'disposition': 'exclude', 'reason': '', 'decision': ''}
        self.put('docs/meta/requirements.json', json.dumps(obj))
        self.cli('adopt', rc=1)
        obj['requirements']['FR-2'].update(reason='outside scope', decision='user:decision-1')
        self.put('docs/meta/requirements.json', json.dumps(obj))
        self.cli('adopt')
        self.put('docs/upstream/prd.md', '# PRD\n## FR-1 Delete\n## FR-2 Restore\n## FR-3 New\n')
        self.assertIn('MDM_COVERAGE', self.cli('check', rc=1))

    def test_semantic_disagreement_cannot_be_ready(self):
        self.setup_story()
        p = self.root / 'comparison.json'
        obj = json.loads(p.read_text())
        obj[0]['resolution'] = 'unresolved'
        p.write_text(json.dumps(obj))
        basis = json.loads(self.cli('inspect', 'ST-001'))['fingerprint']
        self.assertIn('MDM_SEMANTIC', self.cli('ready', 'ST-001', '--basis', basis,
                      '--assessment', 'assessment.json', '--comparison', 'comparison.json',
                      '--reviewed-by', 'user', rc=1))

    def test_handoff_is_bound_to_content_not_date(self):
        self.setup_story()
        self.ready()
        note = {'done': ['implemented'], 'pending': [], 'decisions': ['owner only'],
                'next': ['review result'], 'blockers': []}
        self.put('.tmp/handoff.json', json.dumps(note))
        self.ops('handoff', '--note', '.tmp/handoff.json')
        self.ops('handoff-check')
        self.put('src/app.py', 'new change on same day')
        self.assertIn('MDM_HANDOFF', self.ops('handoff-check', rc=1))

    def test_presentation_plan_has_smaller_read_set(self):
        self.setup_story()
        p = self.root / 'docs/meta/stories.json'
        obj = json.loads(p.read_text())
        obj['stories']['ST-001']['impacts'] = ['presentation']
        p.write_text(json.dumps(obj))
        light = json.loads(self.ops('plan', 'ST-001'))
        obj['stories']['ST-001']['impacts'] = ['authorization', 'data']
        p.write_text(json.dumps(obj))
        heavy = json.loads(self.ops('plan', 'ST-001'))
        self.assertLess(len(light['read']), len(heavy['read']))
        self.assertEqual(heavy['compare_topics'], ['authorization', 'data'])

    def bundle(self):
        self.put('.tmp/prd-new.md', '# PRD\n## FR-1 Delete with confirmation\n')
        obj = {'schema_version': 1, 'files': [{'file': 'prd.md', 'source': 'repo:product.md',
               'input': '.tmp/prd-new.md'}],
               'catalog': json.loads((self.root / 'docs/meta/requirements.json').read_text())}
        self.put('.tmp/bundle.json', json.dumps(obj))
        return json.loads(self.ops('sync-preview', '--bundle', '.tmp/bundle.json'))['basis']

    def test_sync_validates_basis_and_invalidates_old_readiness(self):
        self.setup_story()
        self.ready()
        basis = self.bundle()
        self.ops('sync-apply', '--bundle', '.tmp/bundle.json', '--basis', 'outdated', rc=1)
        self.ops('sync-apply', '--bundle', '.tmp/bundle.json', '--basis', basis)
        self.assertIn('MDM_STALE', self.cli('check', rc=1))
        fresh = json.loads(self.ops('freshness'))
        self.assertIsNotNone(fresh['last_success'])
        self.ops('freshness', '--failed', 'network unavailable')
        failed = json.loads(self.ops('freshness'))
        self.assertEqual(failed['status'], 'failed')
        self.assertEqual(failed['last_success'], fresh['last_success'])

    def test_interrupted_sync_blocks_readers_and_recovers(self):
        self.setup_story()
        self.ready()
        p = self.root / 'docs/upstream/prd.md'
        before = p.read_text()
        import base64
        self.put('docs/meta/sync-pending.json', json.dumps({'schema_version': 1,
                 'before': {'docs/upstream/prd.md': base64.b64encode(p.read_bytes()).decode()}}))
        p.write_text('partial write')
        self.assertIn('MDM_SYNC_PENDING', self.cli('check', rc=1))
        self.ops('sync-recover')
        self.assertEqual(p.read_text(), before)
        self.cli('check')

    def test_real_process_exit_during_sync_is_recoverable(self):
        self.setup_story()
        self.ready()
        basis = self.bundle()
        before = {p.relative_to(self.root).as_posix(): p.read_bytes()
                  for p in (self.root / 'docs').rglob('*') if p.is_file()}
        script = '''import importlib.util,sys,os,pathlib
p=pathlib.Path('.claude/scripts'); sys.path.insert(0,str(p))
spec=importlib.util.spec_from_file_location('sync_test',p/'mdm-contract.py')
e=importlib.util.module_from_spec(spec); sys.modules[spec.name]=e; spec.loader.exec_module(e)
original=e.atomic_bytes
def interrupted(rel, content, exclusive=False):
 original(rel, content, exclusive)
 if rel == 'docs/upstream/prd.md': os._exit(99)
e.atomic_bytes=interrupted
e.operations.main(e,['sync-apply','--bundle','.tmp/bundle.json','--basis',sys.argv[1]])
'''
        p = subprocess.run([sys.executable, '-c', script, basis], cwd=self.root, capture_output=True)
        self.assertEqual(p.returncode, 99, p.stderr)
        self.assertIn('MDM_SYNC_PENDING', self.cli('check', rc=1))
        # The child is confirmed stopped; release its orphaned lock before recovery.
        (self.root / 'docs/meta/.mdm-write.lock').rmdir()
        self.ops('sync-recover')
        after = {p.relative_to(self.root).as_posix(): p.read_bytes()
                 for p in (self.root / 'docs').rglob('*') if p.is_file()}
        self.assertEqual(after, before)
        self.cli('check')

    def test_sync_new_requirement_and_mapping_publish_together(self):
        self.setup_story()
        basis = self.bundle()
        p = self.root / '.tmp/bundle.json'
        obj = json.loads(p.read_text())
        self.put('.tmp/prd-new.md', '# PRD\n## FR-1 Delete\n## FR-2 Restore\n')
        obj['catalog']['requirements']['FR-2'] = {'disposition': 'include', 'reason': '', 'decision': ''}
        p.write_text(json.dumps(obj))
        self.assertIn('MDM_COVERAGE', self.ops('sync-preview', '--bundle', '.tmp/bundle.json', rc=1))
        mapping = (self.root / 'docs/spec/source-map.md').read_text()
        extra = '| FR-2 | prd.md | — | — | M1 | — | 1 | — | ⬜ 대기 | — |\n'
        self.put('.tmp/new-map.md', mapping.replace('## 3.', extra + '## 3.'))
        obj['mapping'] = '.tmp/new-map.md'
        p.write_text(json.dumps(obj))
        basis = json.loads(self.ops('sync-preview', '--bundle', '.tmp/bundle.json'))['basis']
        self.ops('sync-apply', '--bundle', '.tmp/bundle.json', '--basis', basis)
        self.assertIn('FR-2', (self.root / 'docs/spec/source-map.md').read_text())

    def test_handoff_hook_rejects_today_with_new_content(self):
        self.setup_story()
        self.put('docs/status/STATUS.md', '**최종 갱신**: ' + __import__('datetime').date.today().isoformat())
        subprocess.run(['git', 'init', '-q'], cwd=self.root, check=True)
        note = {'done': [], 'pending': [], 'decisions': [], 'next': ['continue'], 'blockers': []}
        self.put('.tmp/handoff.json', json.dumps(note))
        self.ops('handoff', '--note', '.tmp/handoff.json')
        self.put('src/app.py', 'changed after handoff')
        import os
        env = dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root), TMPDIR=str(self.root / '.tmp'))
        hook = KIT / '.claude/hooks/status-updated.sh'
        p = subprocess.run(['bash', str(hook)], input='{}', text=True, env=env, capture_output=True)
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        self.assertIn('인계', p.stderr)

    def test_catalog_zero_matches_and_duplicate_ids_fail(self):
        self.put('docs/upstream/prd.md', '# No requirements\n')
        self.ops('catalog', '--source', 'docs/upstream/prd.md', '--pattern', r'^## (?P<id>FR-\d+)\b', rc=1)

    def test_optional_upstream_examples_do_not_hide_real_broken_reference(self):
        self.put('docs/guides/example.md', 'Optional template: `docs/upstream/plan.md`\n')
        self.ops('refs')
        self.put('docs/plan/stories/ST-002.md', 'Contract: `docs/upstream/plan.md`\n')
        self.assertIn('MDM_REFERENCE', self.ops('refs', rc=1))
        self.put('docs/upstream/prd.md', '## FR-1 First\n## FR-1 Again\n')
        self.ops('catalog', '--source', 'docs/upstream/prd.md', '--pattern', r'^## (?P<id>FR-\d+)\b', rc=1)

    def test_doctor_does_not_infer_remote_activation(self):
        obj = json.loads(self.ops('doctor'))
        self.assertEqual(obj['remote'], {'status': 'unknown', 'reason': 'not queried'})

    def test_product_final_check_and_doctor_run(self):
        import shutil
        for source in KIT.rglob('*'):
            if not source.is_file() or '__pycache__' in source.parts:
                continue
            target = self.root / source.relative_to(KIT)
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        status = self.root / 'docs/status/STATUS.md'
        status.write_text(status.read_text().replace('| — | | | | | |', '| ST-001 | Delete | Main | 🔵 | — | — |'))
        self.setup_story()
        self.ready()
        self.put('.tmp/handoff.json', json.dumps({'done': ['ready'], 'pending': [], 'decisions': [],
                                                'next': ['implement'], 'blockers': []}))
        self.ops('handoff', '--note', '.tmp/handoff.json')
        result = json.loads(self.ops('doctor', '--run'))
        self.assertTrue(result['adopted'])
        self.assertEqual(result['local_check']['status'], 'passed', result)
        status.write_text(status.read_text() + '\nnew decision\n')
        result = json.loads(self.ops('doctor', '--run'))
        self.assertEqual(result['local_check']['status'], 'failed')
        self.assertIn('MDM_HANDOFF', result['local_check']['output'])

    def test_install_seeds_ci_without_overwriting_project_workflow(self):
        target = self.root / 'product'
        target.mkdir()
        installer = KIT.parents[1] / 'scripts/install-kit.sh'
        for mode in [[], ['--upgrade']]:
            p = subprocess.run(['bash', str(installer), str(target), *mode], capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
            workflow = target / '.github/workflows/mdm-check.yml'
            if not mode:
                self.assertIn('mdm-check.sh', workflow.read_text())
                workflow.write_text('project owned workflow')
            else:
                self.assertEqual(workflow.read_text(), 'project owned workflow')

    def test_pilot_distinguishes_rehearsal_and_zero_denominators(self):
        obj = {'kind': 'rehearsal', 'project': 'synthetic', 'change': 'permission change',
               'evidence': ['test_operations.py'],
               'contradictions_before': 1, 'drift_after': 0, 'rework_minutes': 0,
               'questions': 0, 'necessary_questions': 0, 'documents_read': 3,
               'review_candidates': 0, 'affected_candidates': 0, 'false_alarms': 0,
               'check_seconds': 1, 'handoff_errors': 0}
        self.put('.tmp/pilot.json', json.dumps(obj))
        result = json.loads(self.ops('pilot', '--record', '.tmp/pilot.json'))
        self.assertEqual(result['kind'], 'rehearsal')
        self.assertIsNone(result['question_precision'])
        obj['necessary_questions'] = 1
        self.put('.tmp/pilot.json', json.dumps(obj))
        self.ops('pilot', '--record', '.tmp/pilot.json', rc=1)


# Keep inherited helpers but do not run the base cases twice.
for _name in list(fixtures.Contracts.__dict__):
    if _name.startswith('test_'):
        setattr(Operations, _name, None)
