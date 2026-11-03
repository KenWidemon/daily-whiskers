"""Offline guard tests only: never build or launch an app/simulator."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("suite", Path(__file__).with_name("stillness-suite-diagnostic.py"))
suite = importlib.util.module_from_spec(spec)
spec.loader.exec_module(suite)


class SuiteGuards(unittest.TestCase):
    def test_order_is_exact_not_a_set_or_partial_prefix(self):
        expected = ["A/one", "B/two"]
        def log(order):
            return "\n".join(f"Test Case '-[DailyWhiskersUITests.{x.replace('/', ' ')}]' started." for x in order)
        self.assertTrue(suite.suite_order(log(expected), expected)["exact"])
        for order in [expected[::-1], expected[:1], expected + expected[:1], []]:
            self.assertFalse(suite.suite_order(log(order), expected)["exact"])

    def summary(self, count):
        return {"result": "Passed", "totalTestCount": count, "passedTests": count, "failedTests": 0,
                "skippedTests": 0, "expectedFailures": 0, "devicesAndConfigurations": [
                    {"passedTests": count, "failedTests": 0, "device": {"modelName": "iPhone 17 Pro",
                     "osVersion": "26.4.1", "osBuildNumber": "23E254a"}}]}

    def test_exact_counts_and_environment(self):
        for count in (20, 143):
            self.assertTrue(suite.suite_pass(self.summary(count), count))
            for key, value in [("passedTests", count - 1), ("totalTestCount", True),
                               ("failedTests", 1), ("skippedTests", 1), ("expectedFailures", 1)]:
                data = self.summary(count); data[key] = value
                self.assertFalse(suite.suite_pass(data, count))
        data = self.summary(20); data["devicesAndConfigurations"][0]["device"]["osVersion"] = "26.5"
        self.assertFalse(suite.suite_pass(data, 20))
        data = self.summary(143); data["devicesAndConfigurations"][0]["passedTests"] = 206
        self.assertTrue(suite.suite_pass(data, 143, 206))
        self.assertFalse(suite.suite_pass(data, 143, 143))

    def events(self):
        events = []
        def add(phase, **values):
            events.append(dict(phase=phase, pid=42, testID="one", mainThread=True,
                               epoch=len(events) / 10, sequence=len(events) + 1, **values))
        add("trace.install", eventHook=True, actionHook=True)
        add("defaults.attached")
        for value in [True, False]:
            add("touch.beforeDispatch")
            add("control.beforeAction")
            add("binding.before", requested=value)
            add("binding.after", requested=value, stored=value)
            add("appStorage.change", new=value)
        return events

    def test_controls_do_not_require_success_of_second_enable_but_reject_missing_earlier_evidence(self):
        self.assertTrue(suite.trace_controls(self.events())["interpretable_controls"])
        for phase in ["trace.install", "touch.beforeDispatch", "control.beforeAction", "binding.after", "appStorage.change"]:
            events = [e for e in self.events() if e["phase"] != phase]
            # Renumber to independently exercise missing controls, not only gaps.
            for i, event in enumerate(events): event["sequence"] = i + 1
            self.assertFalse(suite.trace_controls(events)["interpretable_controls"], phase)
        events = self.events(); events[3]["sequence"] = 100
        self.assertFalse(suite.trace_controls(events)["interpretable_controls"])
        events = self.events(); events[-1]["testID"] = "other"
        self.assertFalse(suite.trace_controls(events)["interpretable_controls"])

    def test_green_requires_every_gate_and_cleanup(self):
        good = {"status": "completed", "ui_attempts": 1, "stages": dict.fromkeys(["prepare", "resolve", "unit", "ui"], 0),
                "unit_exact_pass": True, "ui_exact_pass": True, "order": {"exact": True},
                "trace_controls": {"interpretable_controls": True}, "video_valid": True, "collection_errors": []}
        self.assertTrue(suite.observation_pass(good, True))
        self.assertFalse(suite.observation_pass(good, False))
        for key, value in [("ui_attempts", 2), ("status", "error"), ("unit_exact_pass", False),
                           ("ui_exact_pass", False), ("order", {}), ("trace_controls", {}),
                           ("video_valid", False), ("collection_errors", ["missing"]), ("stages", {"ui": 0})]:
            altered = copy.deepcopy(good); altered[key] = value
            self.assertFalse(suite.observation_pass(altered, True), key)

    def test_no_local_or_repeat_hosted_execution(self):
        for env in [{}, {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "workflow_dispatch",
                       "GITHUB_REF_NAME": suite.BRANCH, "GITHUB_RUN_ATTEMPT": "2",
                       "GITHUB_REPOSITORY": "KenWidemon/daily-whiskers"}]:
            with patch.dict(suite.os.environ, env, clear=True), patch.object(suite.subprocess, "run") as run:
                with self.assertRaises(SystemExit): suite.main()
                run.assert_not_called()

    def test_failed_unit_stops_before_ui_and_cleans_owned_selection_even_if_collection_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); artifacts = root / "evidence/artifacts"
            def stage(checkout, env, name, command, output, record, deadline):
                if name == "prepare": Path(env["GITHUB_ENV"]).write_text("SIMULATOR_ID=owned\n")
                record["stages"][name] = 65 if name == "unit" else 0
                return record["stages"][name]
            with patch.object(suite, "stage", side_effect=stage) as stages, \
                 patch.object(suite.previous, "verify_device", return_value={"initial_state": "Shutdown"}), \
                 patch.object(suite, "collect", side_effect=OSError("disk error")), \
                 patch.object(suite.previous, "cleanup_owned", return_value=True) as cleanup, \
                 patch.object(suite.subprocess, "Popen") as launch:
                record, cleaned = suite.observe(root, root, artifacts)
            self.assertEqual([c.args[2] for c in stages.call_args_list], ["prepare", "resolve", "unit"])
            self.assertEqual(record["ui_attempts"], 0)
            self.assertEqual(cleanup.call_args.args[0]["device"], "owned")
            self.assertTrue(cleaned); launch.assert_not_called()
            self.assertTrue((artifacts / "observation.json").exists())

    def test_rejected_selection_is_never_claimed_or_mutated(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def prepare(checkout, env, name, command, artifacts, record, deadline):
                Path(env["GITHUB_ENV"]).write_text("SIMULATOR_ID=rejected\n"); return 0
            with patch.object(suite, "stage", side_effect=prepare), \
                 patch.object(suite.previous, "verify_device", side_effect=RuntimeError("wrong runtime")), \
                 patch.object(suite, "collect"), patch.object(suite.previous, "cleanup_owned", return_value=False) as cleanup:
                record, _ = suite.observe(root, root, root / "evidence/artifacts")
            self.assertEqual(cleanup.call_args.args[0], {})
            self.assertEqual(record["ui_attempts"], 0)

    def test_failed_ui_is_one_attempt_with_capture_collection_and_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); calls = []
            def stage(checkout, env, name, command, artifacts, record, deadline):
                calls.append((name, command))
                if name == "prepare": Path(env["GITHUB_ENV"]).write_text("SIMULATOR_ID=owned\n")
                record["stages"][name] = 65 if name == "ui" else 0
                return record["stages"][name]
            with patch.object(suite, "stage", side_effect=stage), \
                 patch.object(suite.previous, "verify_device", return_value={"initial_state": "Booted"}), \
                 patch.object(suite.previous, "output", return_value=json.dumps(dict(self.summary(143), devicesAndConfigurations=[dict(self.summary(143)["devicesAndConfigurations"][0], passedTests=206)]))), \
                 patch.object(suite.previous, "wait_recorder_ready"), \
                 patch.object(suite.previous, "stop_recorder") as stop, \
                 patch.object(suite.previous, "validate_recording") as validate, \
                 patch.object(suite.subprocess, "Popen") as launch, patch.object(suite.time, "sleep"), \
                 patch.object(suite, "collect") as collect, \
                 patch.object(suite.previous, "cleanup_owned", return_value=True) as cleanup:
                record, cleaned = suite.observe(root, root, root / "evidence/artifacts")
            self.assertEqual([n for n, _ in calls], ["prepare", "resolve", "unit", "ui"])
            self.assertEqual(calls[-1][1], ["bash", "ci/test-app.sh", "ui"])
            self.assertEqual(record["ui_attempts"], 1); self.assertEqual(record["stages"]["ui"], 65)
            self.assertFalse(suite.observation_pass(record, cleaned))
            launch.assert_called_once(); stop.assert_called_once(); validate.assert_called_once()
            collect.assert_called_once(); cleanup.assert_called_once()

    def test_recorder_readiness_failure_does_not_launch_ui(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); calls = []
            def stage(checkout, env, name, command, artifacts, record, deadline):
                calls.append(name)
                if name == "prepare": Path(env["GITHUB_ENV"]).write_text("SIMULATOR_ID=owned\n")
                record["stages"][name] = 0; return 0
            with patch.object(suite, "stage", side_effect=stage), \
                 patch.object(suite.previous, "verify_device", return_value={"initial_state": "Booted"}), \
                 patch.object(suite.previous, "output", return_value=json.dumps(dict(self.summary(143), devicesAndConfigurations=[dict(self.summary(143)["devicesAndConfigurations"][0], passedTests=206)]))), \
                 patch.object(suite.previous, "wait_recorder_ready", side_effect=RuntimeError("recorder died")), \
                 patch.object(suite.previous, "stop_recorder") as stop, \
                 patch.object(suite.previous, "validate_recording"), patch.object(suite.subprocess, "Popen"), \
                 patch.object(suite, "collect"), patch.object(suite.previous, "cleanup_owned", return_value=True) as cleanup:
                record, _ = suite.observe(root, root, root / "evidence/artifacts")
            self.assertEqual(calls, ["prepare", "resolve", "unit"])
            self.assertEqual(record["ui_attempts"], 0)
            stop.assert_called_once(); cleanup.assert_called_once()

    def test_timeout_terminates_only_owned_process_group_without_retry(self):
        with tempfile.TemporaryDirectory() as temporary:
            child = Mock(pid=42); child.wait.side_effect = [subprocess.TimeoutExpired("stage", 1), 143]
            with patch.object(suite.subprocess, "Popen", return_value=child) as launch, \
                 patch.object(suite.os, "killpg") as kill, patch.object(suite.time, "monotonic", return_value=1):
                with self.assertRaises(RuntimeError):
                    suite.stage(Path(temporary), {}, "ui", ["bash", "ci/test-app.sh", "ui"],
                                Path(temporary), {"stages": {}}, 2)
            launch.assert_called_once(); kill.assert_called_once_with(42, suite.signal.SIGTERM)


if __name__ == "__main__":
    unittest.main()
