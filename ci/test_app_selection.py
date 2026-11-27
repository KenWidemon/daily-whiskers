"""Exercise the hosted UI command without invoking Xcode or a simulator."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class HostedUISelectionTests(unittest.TestCase):
    def test_ui_command_keeps_every_required_class_without_exclusions(self):
        script = Path(__file__).with_name('test-app.sh').resolve()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tools = root / 'bin'
            tools.mkdir()
            capture = root / 'arguments.json'
            xcodebuild = tools / 'xcodebuild'
            xcodebuild.write_text(
                '#!/usr/bin/env python3\n'
                'import json, os, pathlib, sys\n'
                'pathlib.Path(os.environ["ARGUMENT_CAPTURE"]).write_text(json.dumps(sys.argv[1:]))\n'
            )
            xcodebuild.chmod(0o755)
            lock = root / 'DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
            lock.parent.mkdir(parents=True)
            lock.write_text('{}\n')
            (root / 'Package.resolved.expected').write_bytes(lock.read_bytes())
            environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                               GITHUB_WORKSPACE=str(root), RUNNER_TEMP=str(root),
                               SIMULATOR_ID='selection-test-only', ARGUMENT_CAPTURE=str(capture))
            subprocess.run(['bash', str(script), 'ui'], cwd=root, env=environment,
                           check=True, capture_output=True, text=True, timeout=30)
            arguments = json.loads(capture.read_text())

        self.assertEqual(arguments[0], 'test')
        self.assertEqual(arguments[arguments.index('-scheme') + 1], 'DailyWhiskersInteraction')
        self.assertIn('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING', arguments)
        required = {'RegressionSmokeTests', 'SavedCardsTests', 'StillnessModeTests',
                    'SavedCardsLoadStateTests', 'ReminderUITests', 'MischievousCardsTests'}
        for name in sorted(required):
            with self.subTest(test_class=name):
                self.assertEqual(arguments.count('-only-testing:DailyWhiskersUITests/' + name), 1,
                                 'Select the whole required class exactly once')
        self.assertFalse(any(arg.startswith('-skip-testing') for arg in arguments),
                         'Required UI coverage must not be silently excluded')


if __name__ == '__main__':
    unittest.main()
