"""Check privilege boundaries and execute the actual rehearsal identity preflight."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/release-rehearsal.yml"


class RehearsalWorkflowTests(unittest.TestCase):
    def test_no_privileged_surface_and_only_pinned_checkout_and_report_actions(self):
        text = WORKFLOW.read_text()
        triggers = text.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertEqual(re.findall(r"^  ([a-z_]+):", triggers, re.M), ["workflow_dispatch"])
        self.assertNotRegex(text, r"secrets[.\[]|id-token:|environment:|pull_request_target|self-hosted")
        self.assertIn("permissions:\n  contents: read\n", text)
        self.assertEqual(text.count("permissions:"), 1)
        self.assertIn("persist-credentials: false", text)
        self.assertIn("cancel-in-progress: false", text)
        self.assertIn("runs-on: ubuntu-24.04", text)
        self.assertIn("timeout-minutes: 5", text)
        uses = re.findall(r"uses: (\S+)", text)
        self.assertEqual(uses, ["actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
                               "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"])
        self.assertNotRegex(text, r"xcodebuild|altool|Transporter|curl |wget |security import")
        self.assertIn("path: build/release-rehearsal/report.json", text)
        self.assertNotRegex(text, r"run:.*\$\{\{")

    def test_actual_preflight_rejects_moving_dirty_mismatched_and_injected_inputs(self):
        text = WORKFLOW.read_text()
        step = text.split("- name: Verify controller and candidate identities", 1)[1].split("- name:", 1)[0]
        script = textwrap.dedent(step.split("run: |\n", 1)[1]).strip()
        with tempfile.TemporaryDirectory(prefix="dw-release-git-fixture-") as temporary:
            repo = Path(temporary) / "checkout"
            subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", str(ROOT), str(repo)], check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            sha = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
            base = dict(os.environ, GITHUB_REF="refs/heads/codex/develop", GITHUB_SHA=sha,
                        CONTROLLER_SHA=sha, CANDIDATE_SHA=sha, TAG_OBJECT="")
            def execute(**updates):
                return subprocess.run(["bash", "-c", script], cwd=repo, env=dict(base, **updates),
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode
            self.assertEqual(execute(), 0)
            # Annotated tag objects are private fixture objects, never repository refs.
            tag = f"object {sha}\ntype commit\ntag fixture\ntagger Fixture <fixture@example.invalid> 1 +0000\n\nfixture\n"
            tag_object = subprocess.check_output(["git", "mktag"], input=tag, cwd=repo, text=True).strip()
            self.assertEqual(execute(TAG_OBJECT=tag_object), 0)
            earlier = subprocess.check_output(["git", "rev-parse", "HEAD^"], cwd=repo, text=True).strip()
            self.assertNotEqual(execute(TAG_OBJECT=tag_object, CANDIDATE_SHA=earlier), 0)
            for updates in ({"GITHUB_REF": "refs/pull/1/merge"}, {"CONTROLLER_SHA": "f" * 40},
                            {"CANDIDATE_SHA": "codex/develop"}, {"CANDIDATE_SHA": "$(touch escaped)"},
                            {"CANDIDATE_SHA": "f" * 40}, {"TAG_OBJECT": sha}, {"TAG_OBJECT": "../../outside"}):
                with self.subTest(updates=updates):
                    self.assertNotEqual(execute(**updates), 0)
            self.assertFalse((repo / "escaped").exists())
            (repo / "dirty").write_text("fixture dirty checkout")
            self.assertNotEqual(execute(), 0)


if __name__ == "__main__":
    unittest.main()
