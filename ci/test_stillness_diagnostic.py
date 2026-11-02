"""Guard against reporting partial, repeated, mismatched or unobserved runs as a paired pass."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("diagnostic", Path(__file__).with_name("stillness-diagnostic.py"))
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


class EvidenceGuards(unittest.TestCase):
    def test_local_invocation_or_hosted_retry_cannot_execute(self):
        for env in [{}, {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "workflow_dispatch",
                       "GITHUB_REF_NAME": diagnostic.BRANCH, "GITHUB_RUN_ATTEMPT": "2",
                       "GITHUB_REPOSITORY": "KenWidemon/daily-whiskers"}]:
            with patch.dict(diagnostic.os.environ, env, clear=True), patch.object(diagnostic.subprocess, "run") as run:
                with self.assertRaises(SystemExit):
                    diagnostic.main()
                run.assert_not_called()

    def summary(self):
        return {"result": "Passed", "totalTestCount": 1, "passedTests": 1, "failedTests": 0,
                "skippedTests": 0, "expectedFailures": 0, "devicesAndConfigurations": [
                    {"passedTests": 1, "failedTests": 0, "device": {"modelName": "iPhone 17 Pro",
                     "osVersion": "26.4.1", "osBuildNumber": "23E254a"}}]}

    def test_only_one_unskipped_pass_on_target_runtime_is_accepted(self):
        self.assertTrue(diagnostic.exact_test_pass(self.summary()))
        for key, value in [("totalTestCount", 2), ("passedTests", True), ("failedTests", 1),
                           ("skippedTests", 1), ("expectedFailures", 1), ("result", "Failed")]:
            data = self.summary(); data[key] = value
            self.assertFalse(diagnostic.exact_test_pass(data), key)
        data = self.summary(); data["devicesAndConfigurations"][0]["passedTests"] = 2
        self.assertFalse(diagnostic.exact_test_pass(data))
        data = self.summary(); data["devicesAndConfigurations"][0]["device"]["osVersion"] = "26.5"
        self.assertFalse(diagnostic.exact_test_pass(data))

    def test_old_and_malformed_trace_lines_cannot_supply_current_coverage(self):
        raw = "noise\nDW_STILLNESS_DIAG invalid\nDW_STILLNESS_DIAG " + json.dumps({"epoch": 10, "phase": "old"})
        raw += "\nDW_STILLNESS_DIAG " + json.dumps({"epoch": 20, "phase": "current"})
        self.assertEqual([x["phase"] for x in diagnostic.trace_events(raw, 15)], ["current"])

    def test_absent_native_action_is_a_limit_not_a_delivery_verdict(self):
        events = [{"testID": "one", "phase": phase} for phase in
                  ["touch.beforeDispatch", "binding.before", "defaults.attached"]]
        events.append({"testID": "one", "phase": "trace.install", "eventHook": True, "actionHook": True})
        coverage = diagnostic.trace_coverage(events)
        self.assertTrue(coverage["minimum_trace_present"])
        self.assertFalse(coverage["native_action_observed"])
        events.append({"testID": "second", "phase": "binding.before"})
        self.assertFalse(diagnostic.trace_coverage(events)["minimum_trace_present"])

    def test_failure_partial_pair_or_missing_capture_cannot_be_green(self):
        good = {"status": "completed", "test_attempts": 1, "build_exit": 0,
                "test_exit": 0, "exact_test_pass": True, "video_present": True,
                "collection_errors": [], "trace_coverage": {"minimum_trace_present": True}}
        self.assertFalse(diagnostic.pair_pass({"baseline": good}))
        records = {"baseline": copy.deepcopy(good), "candidate": copy.deepcopy(good)}
        self.assertTrue(diagnostic.pair_pass(records))
        for key, value in [("status", "error"), ("test_attempts", 2), ("build_exit", 65),
                           ("test_exit", 65), ("exact_test_pass", False), ("video_present", False),
                           ("collection_errors", ["missing log"]), ("trace_coverage", {})]:
            changed = copy.deepcopy(records); changed["baseline"][key] = value
            self.assertFalse(diagnostic.pair_pass(changed), key)


if __name__ == "__main__":
    unittest.main()
