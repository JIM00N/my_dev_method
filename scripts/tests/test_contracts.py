"""Product-level contract evidence regressions; all mutations stay in temporary repos."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

KIT = Path(__file__).resolve().parents[2] / 'templates/dev-kit'
SLOTS = ['state', 'authorization', 'rules', 'data', 'exceptions', 'presentation',
         'checks', 'preconditions', 'trigger', 'action', 'result', 'acceptance']


class Contracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copytree(KIT / '.claude/scripts', self.root / '.claude/scripts',
                        ignore=shutil.ignore_patterns('__pycache__'))
        self.put('docs/spec/source-map.md', '''# source-map
## 2. 요구사항 매핑표
| ID | 출처 | 화면 | 준비 | 마일스톤 | 사이클 | 조건 수 | 테스트 | 상태 | 재검토 |
|---|---|---|---|---|---|---|---|---|---|
| FR-1 | prd.md §1 | — | ✅ | M1 | C01 | 1 | test_ok | 🔵 진행 중 | — |
## 3. 화면 매핑표
| ID | 이름 | 출처 | 요구사항 |
|---|---|---|---|
''')
        self.put('docs/spec/domain.md', '# Domain\nOnly the owner may delete.\n')
        self.put('docs/plan/stories/ST-001-demo.md', '# ST-001\nDelete an order.\n')
        self.put('src/app.py', 'def allowed(owner):\n    return owner\n')
        self.put('tests/test_app.py', 'def test_ok():\n    assert True\n')
        self.put('assessment.json', json.dumps({s: {'status': 'answered', 'evidence': 'approved contract §1'} for s in SLOTS}))
        self.put('docs/upstream/prd.md', '# PRD\n## FR-1 Delete\n')
        self.put('docs/meta/requirements.json', json.dumps({'schema_version': 1,
            'sources': [{'file': 'docs/upstream/prd.md', 'pattern': r'^## (?P<id>FR-\d+)\b'}],
            'requirements': {'FR-1': {'disposition': 'include', 'reason': '', 'decision': ''}}}))
        self.put('comparison.json', json.dumps([{'topic': 'behavior', 'authority': 'docs/spec/domain.md#Domain',
            'consumer': 'docs/plan/stories/ST-001-demo.md#ST-001', 'actor': 'owner', 'condition': 'owned order',
            'action': 'delete', 'result': 'removed', 'resolution': 'aligned', 'reason': 'reviewed owner rule'}]))

    def put(self, path, data):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(data, encoding='utf-8')
        return p

    def cli(self, *args, rc=0):
        p = subprocess.run([sys.executable, str(self.root / '.claude/scripts/mdm-contract.py'), *args],
                           cwd=self.root, text=True, capture_output=True)
        self.assertEqual(p.returncode, rc, p.stdout + p.stderr)
        return p.stdout

    def setup_story(self):
        self.cli('adopt')
        self.cli('register', 'ST-001', '--requirement', 'FR-1',
                 '--document', 'docs/plan/stories/ST-001-demo.md',
                 '--input', 'docs/spec/domain.md', '--criterion', 'FR-1/AC-1=Suite::test_ok')

    def ready(self):
        p = self.root / 'comparison.json'
        matrix = json.loads(p.read_text())
        matrix[0]['authority'] = 'docs/spec/domain.md#' + (self.root / 'docs/spec/domain.md').read_text().splitlines()[0]
        p.write_text(json.dumps(matrix))
        basis = json.loads(self.cli('inspect', 'ST-001'))['fingerprint']
        self.cli('ready', 'ST-001', '--basis', basis, '--assessment', 'assessment.json',
                 '--comparison', 'comparison.json', '--reviewed-by', 'user:fixture')

    def model(self):
        path = self.root / '.claude/scripts/mdm_model.py'
        spec = importlib.util.spec_from_file_location('fixture_model', path)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        return m

    def test_missing_configuration_is_not_success(self):
        self.cli('check', rc=1)

    def test_heading_corruption_is_not_initialization(self):
        self.setup_story()
        p = self.root / 'docs/spec/source-map.md'
        p.write_text(p.read_text().replace('## 2.', '##'))
        self.assertIn('MDM_SCHEMA', self.cli('check', rc=1))

    def test_readiness_changes_without_editing_status_or_receipt(self):
        self.setup_story()
        self.ready()
        self.cli('check')
        receipts = list((self.root / 'docs/evidence/readiness').rglob('*.json'))
        before = {str(p): p.read_bytes() for p in receipts}
        self.put('docs/spec/domain.md', '# Domain\nAdmins may delete too.\n')
        self.assertIn('MDM_STALE', self.cli('check', rc=1))
        self.assertEqual(before, {str(p): p.read_bytes() for p in receipts})
        self.ready()
        self.cli('check')
        self.assertEqual(len(list((self.root / 'docs/evidence/readiness').rglob('*.json'))), 2)

    def test_old_review_basis_cannot_stamp_new_contract(self):
        self.setup_story()
        basis = json.loads(self.cli('inspect', 'ST-001'))['fingerprint']
        self.put('docs/spec/domain.md', 'Changed after review\n')
        self.assertIn('MDM_STALE', self.cli('ready', 'ST-001', '--basis', basis,
                      '--assessment', 'assessment.json', '--reviewed-by', 'user', rc=1))

    def test_incomplete_assessment_cannot_be_ready(self):
        self.setup_story()
        self.put('assessment.json', '{}')
        basis = json.loads(self.cli('inspect', 'ST-001'))['fingerprint']
        self.assertIn('MDM_ASSESSMENT', self.cli('ready', 'ST-001', '--basis', basis,
                      '--assessment', 'assessment.json', '--reviewed-by', 'user', rc=1))

    def test_report_and_model_keep_br_rows(self):
        p = self.root / 'docs/spec/source-map.md'
        text = p.read_text().replace('prd.md §1', 'prd.md §1<br>details')
        hdr, rows = self.model().section_table(text, 2)
        self.assertEqual(len(rows), 1)
        self.assertIn('<br>', rows[0][hdr.index('출처')])
        self.assertEqual(self.model().section_table(text.replace('\n| FR-', '\n  | FR-'), 2), (hdr, rows))

    def test_duplicate_id_and_invalid_status_fail(self):
        for old, new in [('🔵 진행 중', '완료'), ('| FR-1 |', '| FR-1 |')]:
            p = self.root / 'docs/spec/source-map.md'
            original = p.read_text()
            changed = original.replace(old, new)
            if old == new:
                row = next(x for x in original.splitlines() if x.startswith('| FR-1 |'))
                changed = original.replace(row, row + '\n' + row)
            p.write_text(changed)
            self.assertIn('MDM_SCHEMA', self.cli('adopt', rc=1))
            p.write_text(original)

    def junit_command(self, status='pass', mutate=False):
        body = '<skipped/>' if status == 'skip' else '<failure/>' if status == 'fail' else ''
        xml = '<testsuite><testcase classname="Suite" name="test_ok">' + body + '</testcase></testsuite>'
        code = 'import os,pathlib; pathlib.Path(os.environ["MDM_JUNIT_OUTPUT"]).write_text(' + repr(xml) + ')'
        if mutate:
            code += '; pathlib.Path("src/app.py").write_text("changed during execution")'
        return [sys.executable, '-c', code]

    def test_completion_requires_current_actual_test_report(self):
        self.setup_story()
        self.ready()
        p = self.root / 'docs/spec/source-map.md'
        p.write_text(p.read_text().replace('🔵 진행 중', '✅ 완료'))
        self.assertIn('MDM_VERIFICATION', self.cli('check', rc=1))
        self.cli('verify', 'ST-001', '--', *self.junit_command())
        self.cli('check')
        self.put('src/app.py', 'changed after testing\n')
        self.assertIn('MDM_VERIFICATION', self.cli('check', rc=1))

    def test_skip_failure_missing_report_and_concurrent_edit_fail(self):
        self.setup_story()
        self.ready()
        for cmd in [self.junit_command('skip'), self.junit_command('fail'),
                    [sys.executable, '-c', 'pass'], self.junit_command(mutate=True)]:
            self.cli('verify', 'ST-001', '--', *cmd, rc=1)

    def test_failed_latest_attempt_revokes_previous_success(self):
        self.setup_story()
        self.ready()
        self.cli('verify', 'ST-001', '--', *self.junit_command())
        p = self.root / 'docs/spec/source-map.md'
        p.write_text(p.read_text().replace('🔵 진행 중', '✅ 완료'))
        self.cli('check')
        self.cli('verify', 'ST-001', '--', *self.junit_command('fail'), rc=1)
        self.assertIn('MDM_VERIFICATION', self.cli('check', rc=1))

    def test_render_recomputes_ready_without_refreshing_evidence(self):
        self.setup_story()
        self.ready()
        self.cli('render')
        self.cli('check')
        self.put('docs/spec/domain.md', 'new contract')
        self.cli('render')
        self.assertIn('❌ 재판정', (self.root / 'docs/spec/source-map.md').read_text())
        self.cli('check', rc=1)

    def test_story_archive_preserves_evidence(self):
        self.setup_story()
        self.ready()
        dest = self.root / 'docs/plan/archive/stories/ST-001-demo.md'
        dest.parent.mkdir(parents=True)
        (self.root / 'docs/plan/stories/ST-001-demo.md').rename(dest)
        self.cli('check')

    def test_dependency_removal_invalidates_readiness(self):
        self.setup_story()
        self.put('docs/spec/stack.md', '# Stack\nPython\n')
        p = self.root / 'docs/meta/stories.json'
        obj = json.loads(p.read_text())
        obj['stories']['ST-001']['inputs'].append('docs/spec/stack.md')
        p.write_text(json.dumps(obj))
        self.ready()
        # Still valid schema; both files remain in the conservative spec baseline.
        # Only the explicit dependency definition changes.
        obj['stories']['ST-001']['inputs'].remove('docs/spec/stack.md')
        p.write_text(json.dumps(obj))
        self.assertIn('MDM_STALE', self.cli('check', rc=1))

    def test_new_code_file_invalidates_verification(self):
        self.setup_story()
        self.ready()
        self.cli('verify', 'ST-001', '--', *self.junit_command())
        p = self.root / 'docs/spec/source-map.md'
        p.write_text(p.read_text().replace('🔵 진행 중', '✅ 완료'))
        self.cli('check')
        self.put('src/new.py', 'new behavior\n')
        self.cli('check', rc=1)

    def test_full_kit_shell_report_and_archive_flow(self):
        for source in KIT.rglob('*'):
            if not source.is_file() or '__pycache__' in source.parts:
                continue
            dest = self.root / source.relative_to(KIT)
            if not dest.exists():
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, dest)
        status = self.root / 'docs/status/STATUS.md'
        status.write_text(status.read_text().replace('| — | | | | | |', '| ST-001 | Delete | Main | 🔵 | — | — |'))
        self.setup_story()
        self.ready()
        def shell(rc):
            p = subprocess.run(['bash', str(self.root / '.claude/scripts/check-consistency.sh')],
                               cwd=self.root, text=True, capture_output=True)
            self.assertEqual(p.returncode, rc, p.stdout + p.stderr)
        shell(0)
        self.put('docs/spec/domain.md', 'Changed permission')
        shell(1)
        p = subprocess.run([sys.executable, str(self.root / '.claude/scripts/report.py'), 'ready'],
                           cwd=self.root, text=True, capture_output=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        html = next((self.root / 'docs/reports').glob('ready-*.html')).read_text()
        self.assertIn('재검토 필요', html)
        self.assertIn('정합성 검사 실패', html)
        self.ready()
        self.cli('verify', 'ST-001', '--', *self.junit_command())
        shell(0)

    def test_installer_preserves_evidence_on_upgrade(self):
        target = self.root / 'product'
        target.mkdir()
        installer = KIT.parents[1] / 'scripts/install-kit.sh'
        for mode in [[], ['--upgrade']]:
            p = subprocess.run(['bash', str(installer), str(target), *mode], text=True, capture_output=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
            for name in ['mdm-contract.py', 'mdm_model.py']:
                deployed = target / '.claude/scripts' / name
                self.assertEqual(deployed.read_bytes(), (KIT / '.claude/scripts' / name).read_bytes())
                self.assertTrue(os.access(deployed, os.X_OK))
            marker = target / 'docs/evidence/readiness/keep.json'
            config = target / 'docs/meta/project.json'
            if not mode:
                marker.parent.mkdir(parents=True)
                marker.write_text('project evidence')
                config.parent.mkdir(parents=True)
                config.write_text('project config')
            else:
                self.assertEqual(marker.read_text(), 'project evidence')
                self.assertEqual(config.read_text(), 'project config')

    def test_init_is_not_allowed_after_adoption(self):
        self.setup_story()
        self.assertIn('MDM_SCHEMA', self.cli('check', '--init', rc=1))

    def test_missing_input_and_symlink_do_not_get_stamped(self):
        self.setup_story()
        p = self.root / 'docs/spec/domain.md'
        p.unlink()
        self.cli('inspect', 'ST-001', rc=1)
        p.symlink_to(self.root / 'src/app.py')
        self.assertIn('MDM_PATH', self.cli('inspect', 'ST-001', rc=1))

    def test_blank_line_render_does_not_duplicate_rows(self):
        self.setup_story()
        self.ready()
        p = self.root / 'docs/spec/source-map.md'
        p.write_text(p.read_text().replace('\n| FR-1', '\n\n| FR-1'))
        self.cli('render')
        self.cli('check')
        self.assertEqual(p.read_text().count('| FR-1 |'), 1)

    def test_register_rejects_invalid_criteria_without_mutation(self):
        self.cli('adopt')
        p = self.root / 'docs/meta/stories.json'
        before = p.read_bytes()
        self.cli('register', 'ST-001', '--requirement', 'FR-1', '--document',
                 'docs/plan/stories/ST-001-demo.md', '--input', 'docs/spec/domain.md',
                 '--criterion', 'FR-9/AC-1=Suite::test_ok', rc=1)
        self.assertEqual(p.read_bytes(), before)

    def test_render_preserves_hidden_examples_and_accepts_indented_heading(self):
        p = self.root / 'docs/spec/source-map.md'
        example = '<!--\n## 2. Example\n| ID | example |\n|---|---|\n-->\n'
        example += '```md\n## 2. Fenced example\n| ID | example |\n```\n'
        p.write_text(example + p.read_text().replace('## 2.', '  ## 2.'))
        self.setup_story()
        self.ready()
        self.cli('render')
        self.cli('check')
        self.assertTrue(p.read_text().startswith(example))

    def test_render_escaped_pipe_keeps_contract_fingerprint(self):
        p = self.root / 'docs/spec/source-map.md'
        p.write_text(p.read_text().replace('prd.md §1', r'prd.md §1\|§2'))
        self.setup_story()
        self.ready()
        self.cli('render')
        self.cli('check')
        first = p.read_bytes()
        self.cli('render')
        self.assertEqual(p.read_bytes(), first)


if __name__ == '__main__':
    unittest.main()
