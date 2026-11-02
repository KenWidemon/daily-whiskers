"""Guard against reporting partial, repeated, mismatched or unobserved runs as a paired pass."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
import subprocess
import tempfile
from unittest.mock import patch, Mock

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
                "test_exit": 0, "exact_test_pass": True, "video_valid": True,
                "collection_errors": [], "trace_coverage": {"minimum_trace_present": True}}
        self.assertFalse(diagnostic.pair_pass({"baseline": good}))
        records = {"baseline": copy.deepcopy(good), "candidate": copy.deepcopy(good)}
        self.assertTrue(diagnostic.pair_pass(records))
        for key, value in [("status", "error"), ("test_attempts", 2), ("build_exit", 65),
                           ("test_exit", 65), ("exact_test_pass", False), ("video_valid", False),
                           ("collection_errors", ["missing log"]), ("trace_coverage", {})]:
            changed = copy.deepcopy(records); changed["baseline"][key] = value
            self.assertFalse(diagnostic.pair_pass(changed), key)

    def valid_recording(self):
        return ({"spawn_monotonic": 100.0, "ready_monotonic": 100.1,
                 "test_start_monotonic": 101.0, "test_end_monotonic": 111.0,
                 "stop_monotonic": 112.0, "intentional_stop": True,
                 "exit_before_stop": None, "exit": 0},
                {"decoded_all": True, "frame_count": 360, "first_pts": 0.0,
                 "last_pts": 11.9, "max_frame_gap": 1 / 30})

    def test_recording_requires_successful_intentional_stop_and_decoded_coverage(self):
        timing, media = self.valid_recording()
        self.assertTrue(diagnostic.recording_valid(timing, media))
        held_frame = dict(media); held_frame["max_frame_gap"] = 5.0
        self.assertTrue(diagnostic.recording_valid(timing, held_frame))
        for key, value in [("exit", 1), ("exit", -2), ("exit_before_stop", 0),
                           ("intentional_stop", False), ("ready_monotonic", 102.0)]:
            altered = dict(timing); altered[key] = value
            self.assertFalse(diagnostic.recording_valid(altered, media), key)
        for key, value in [("decoded_all", False), ("last_pts", 3.0), ("first_pts", 2.0),
                           ("frame_count", 1)]:
            altered = dict(media); altered[key] = value
            self.assertFalse(diagnostic.recording_valid(timing, altered), key)

    def test_unexpected_recorder_exit_is_preserved_and_rejected(self):
        for exit_code in (0, 1):
            video = Mock(pid=42); video.poll.return_value = exit_code; video.wait.return_value = exit_code
            timing, _ = self.valid_recording(); errors = []
            with patch.object(diagnostic.os, "killpg") as kill:
                diagnostic.stop_recorder(video, timing, errors)
            kill.assert_not_called()
            self.assertEqual(timing["exit"], exit_code)
            self.assertFalse(timing["intentional_stop"])
            self.assertTrue(errors)

    def test_nonempty_but_truncated_or_failed_media_cannot_satisfy_pair(self):
        for exit_code, last_pts in [(1, 11.9), (0, 3.0)]:
            timing, media = self.valid_recording(); timing["exit"] = exit_code; media["last_pts"] = last_pts
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); (root / "active-display.mp4").write_bytes(b"nonempty partial MP4")
                record = {"recorder": timing, "video_present": True, "collection_errors": []}
                result = subprocess.CompletedProcess([], 0, json.dumps(media), "")
                with patch.object(diagnostic.subprocess, "run", return_value=result):
                    diagnostic.validate_recording(root, root, record)
                self.assertFalse(record["video_valid"])
                self.assertTrue(record["collection_errors"])
                self.assertTrue((root / "active-display.mp4").exists())

    def test_rejected_candidate_never_replaces_owned_cleanup_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); calls = []
            def revision(name, sha, checkout, repo, artifacts, packages, owner, ownership_path):
                record = {"source": sha, "test_attempts": 1 if name == "baseline" else 0}
                try:
                    diagnostic.claim_and_boot("A" if name == "baseline" else "B", owner, ownership_path, record)
                except RuntimeError as error:
                    record.update(status="error", error=str(error))
                return record
            def command(args, **kwargs):
                calls.append(args)
                return subprocess.CompletedProcess(args, 0, "", "")
            environment = {"initial_state": "Shutdown"}
            inventory = json.dumps({"devices": {"runtime": [{"udid": "A", "state": "Shutdown"}]}})
            with patch.object(diagnostic, "run_revision", side_effect=revision), \
                 patch.object(diagnostic, "verify_device", return_value=environment) as verify, \
                 patch.object(diagnostic.subprocess, "run", side_effect=command), \
                 patch.object(diagnostic, "output", return_value=inventory):
                records, cleaned = diagnostic.run_pair(root, root, {"baseline": root, "candidate": root})
            verify.assert_called_once_with("A")
            self.assertTrue(cleaned)
            self.assertFalse(diagnostic.pair_pass(records))
            self.assertEqual(records["candidate"]["rejected_device"], "B")
            self.assertNotIn("device", records["candidate"])
            self.assertTrue(all("B" not in args for args in calls))
            self.assertIn(["xcrun", "simctl", "shutdown", "A"], calls)
            self.assertEqual(json.loads((root / "ownership.json").read_text())["device"], "A")

    def test_boot_failure_still_cleans_previously_recorded_owner(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); calls = []
            def revision(name, sha, checkout, repo, artifacts, packages, owner, ownership_path):
                diagnostic.claim_and_boot("A", owner, ownership_path, {})
            def command(args, **kwargs):
                calls.append(args)
                if "bootstatus" in args:
                    self.assertEqual(json.loads((root / "ownership.json").read_text())["device"], "A")
                    raise subprocess.CalledProcessError(1, args)
                return subprocess.CompletedProcess(args, 0, "", "")
            inventory = json.dumps({"devices": {"runtime": [{"udid": "A", "state": "Shutdown"}]}})
            with patch.object(diagnostic, "run_revision", side_effect=revision), \
                 patch.object(diagnostic, "verify_device", return_value={"initial_state": "Shutdown"}), \
                 patch.object(diagnostic.subprocess, "run", side_effect=command), \
                 patch.object(diagnostic, "output", return_value=inventory):
                with self.assertRaises(subprocess.CalledProcessError):
                    diagnostic.run_pair(root, root, {"baseline": root, "candidate": root})
            self.assertIn(["xcrun", "simctl", "shutdown", "A"], calls)
            self.assertEqual(json.loads((root / "cleanup.json").read_text())["verified_state"], "Shutdown")


if __name__ == "__main__":
    unittest.main()
