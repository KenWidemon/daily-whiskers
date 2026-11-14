import re
import unittest
from pathlib import Path
import diagnostic as d
ROOT=Path(__file__).resolve().parent.parent

class CardsWorkflow(unittest.TestCase):
    def test_disposable_workflow_is_not_acceptance(self):
        text = (ROOT / '.github/workflows/ios.yml').read_text()
        self.assertIn('  workflow_dispatch:', text)
        self.assertNotIn('  pull_request:', text)
        self.assertNotIn('  push:', text)
        self.assertNotIn('name: CI Gate', text)
        self.assertNotIn('actions/cache', text)
        self.assertNotIn('matrix:', text)
        self.assertNotIn('strategy:', text)
        self.assertIn('DIAGNOSTIC_STAGE: cards-largest', text)
        self.assertNotIn('startup-reminder', text)
        self.assertIn('timeout-minutes: 60', text)
        self.assertEqual(text.count('run-stage.py init-budget 2700'), 1)
        self.assertEqual(text.count('diagnostic.py test --stage'), 1)
        self.assertNotIn('Second selected method', text)
        self.assertIn("github.run_attempt == 1", text)
        self.assertIn('expected_source_sha:', text)
        self.assertIn('build/Diagnostic-*.xcresult', text)
        self.assertIn('retention-days: 30', text)
        self.assertIn('include-hidden-files: true', text)
        upload = text.split('name: Upload all raw diagnostic evidence', 1)[1]
        self.assertIn('timeout-minutes: 5', upload)
        self.assertLess(text.index('diagnostic.py export'), text.index('simulator.py cleanup'))
        self.assertNotIn('policy.py gate', text)

    def test_workflow_manages_launch_under_one_original_budget(self):
        text = (ROOT / '.github/workflows/ios.yml').read_text()
        steps = re.split(r'^      - ', text, flags=re.M)[1:]
        commands = []
        for step in steps[:8]:
            run = re.search(r'^        run: (.+)$', step, re.M)
            commands.append(run[1] if run else step.splitlines()[0].split('@', 1)[0])
        selected = 'python3 ci/run-stage.py "$DIAGNOSTIC_STAGE" python3 ci/diagnostic.py test --stage "$DIAGNOSTIC_STAGE"'
        self.assertEqual(commands, [
            'uses: actions/checkout', '|',
            'python3 ci/run-stage.py init-budget 2700',
            'python3 ci/run-stage.py prepare bash ci/prepare-app.sh',
            'python3 ci/run-stage.py diagnostic-preflight python3 ci/diagnostic.py preflight',
            'python3 ci/run-stage.py resolve bash ci/test-app.sh resolve',
            'python3 ci/run-stage.py diagnostic-build python3 ci/diagnostic.py build',
            selected])
        self.assertIn('ref: ${{ github.sha }}', steps[0])
        self.assertIn('test "$GITHUB_SHA" = "$EXPECTED_SOURCE_SHA"', steps[1])
        self.assertIn('test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"', steps[1])
        self.assertIn('echo "TESTED_SHA=$(git rev-parse HEAD)" >> "$GITHUB_ENV"', steps[1])
        self.assertEqual(text.count('init-budget'), 1)
        self.assertNotIn('diagnostic.py boot', text)
        self.assertNotIn('simctl boot', text)
        self.assertNotIn('bootstatus', text)
        self.assertFalse(hasattr(d, 'boot'))
        self.assertIn("github.ref == 'refs/heads/codex/ci-cards-focused-20261114'", text)
        self.assertNotIn('CI_EXECUTION_DEADLINE', text)  # No per-stage deadline reset.
