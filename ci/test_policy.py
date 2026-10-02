import itertools
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from policy import classify, docs_only, gate


class PolicyTests(unittest.TestCase):
    def test_allowlist(self):
        self.assertTrue(docs_only(["docs/testing.md", "DailyWhiskers/README.md", "AGENTS.md"]))
        for path in ["README.md", "docs/tool.py", "docs/../project.yml", "project.yml", "ci/policy.py", ".github/workflows/ios.yml", "Package.resolved", "DailyWhiskers/App.swift", "DailyWhiskers/Assets.xcassets/image.png", "DailyWhiskersTests/Test.swift", "docs/a.md\napp.swift"]:
            with self.subTest(path=path):
                self.assertFalse(docs_only(["docs/testing.md", path]))
        self.assertFalse(docs_only([]))

    def test_all_gate_combinations(self):
        states = ["success", "failure", "cancelled", "skipped", "timed_out", "", None]
        for mode, classifier, checks, app in itertools.product(["docs", "full", "", None], states, states, states):
            needs = {"classify": {"result": classifier, "outputs": {"mode": mode}}, "checks": {"result": checks}, "build-and-test": {"result": app}}
            expected = classifier == checks == "success" and ((mode == "docs" and app == "skipped") or (mode == "full" and app == "success"))
            self.assertEqual(gate(needs), expected, needs)
        self.assertFalse(gate({}))

    def test_diff_failure_defaults_full(self):
        with patch("policy.subprocess.check_output", side_effect=OSError):
            self.assertEqual(classify("base", "head"), "full")

    def test_real_diff_rename_delete_and_unusual_filename(self):
        with tempfile.TemporaryDirectory() as directory:
            original = os.getcwd()
            try:
                os.chdir(directory)
                def git(*args):
                    return subprocess.check_output(["git", *args], stderr=subprocess.DEVNULL, text=True).strip()
                git("init")
                git("config", "user.email", "ci@example.invalid")
                git("config", "user.name", "CI Test")
                Path("docs").mkdir()
                Path("docs/a.md").write_text("# Original\n")
                git("add", ".")
                git("commit", "-m", "base")
                base = git("rev-parse", "HEAD")
                Path("docs/a.md").rename("docs/a space.md")
                git("add", "-A")
                git("commit", "-m", "docs rename")
                self.assertEqual(classify(base, "HEAD"), "docs")
                Path("docs/a space.md").rename("app.swift")
                git("add", "-A")
                git("commit", "-m", "rename to app")
                self.assertEqual(classify(base, "HEAD"), "full")
                Path("app.swift").unlink()
                git("add", "-A")
                git("commit", "-m", "delete")
                self.assertEqual(classify(base, "HEAD"), "docs")
                Path("docs/odd\nname.md").write_text("# Odd\n")
                git("add", "-A")
                git("commit", "-m", "unusual name")
                self.assertEqual(classify(base, "HEAD"), "docs")
            finally:
                os.chdir(original)


if __name__ == "__main__":
    unittest.main()
