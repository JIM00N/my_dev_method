#!/usr/bin/env python3
"""Repeatable synthetic rehearsal; never report this as a real-product pilot."""
import json
from pathlib import Path
import sys
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent / 'tests'))
from test_operations import Operations

CASES = [
    'test_unmapped_upstream_requirement_fails',
    'test_semantic_disagreement_cannot_be_ready',
    'test_sync_new_requirement_and_mapping_publish_together',
    'test_real_process_exit_during_sync_is_recoverable',
    'test_handoff_is_bound_to_content_not_date',
    'test_install_seeds_ci_without_overwriting_project_workflow',
]


def main():
    start = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(Operations(name) for name in CASES))
    print(json.dumps({'kind': 'rehearsal', 'cases': CASES, 'run': result.testsRun,
                      'failures': len(result.failures), 'errors': len(result.errors),
                      'seconds': round(time.monotonic() - start, 3),
                      'product_effect': 'not measured',
                      'human_questions': None, 'human_documents_read': None}, ensure_ascii=False, indent=2))
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
