"""Hermetic evidence rejection and watchdog checks; no app execution."""
import copy
import importlib.util
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import uuid

spec = importlib.util.spec_from_file_location("capture", Path(__file__).with_name("first-enable-capture.py"))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)
FIXTURE = "12345678-1234-1234-1234-123456789012"
SESSION = "87654321-4321-4321-4321-210987654321"


def example():
    events = ["installed limit=256", f"fixture id={FIXTURE} session={SESSION} fresh=true",
              "attached native=1 registered=true on=false enabled=true", "window-attached native=1",
              "before phase=0 input=1 associatedNative=1 valid=true on=false enabled=true hidden=false",
              "after phase=0 input=1 associatedNative=1 valid=true on=false",
              "before phase=3 input=1 associatedNative=1 valid=true on=false enabled=true hidden=false",
              "after phase=3 input=1 associatedNative=1 valid=true on=false",
              "binding value=true input=1 associatedNative=1 valid=true",
              "valueChanged native=1 input=1 associatedNative=1 valid=true on=false",
              "command-begin command=1 value=true input=1 associatedNative=1 valid=true",
              "command-end command=1 input=1 associatedNative=1 valid=true enabled=true busy=false error=false storageBlocked=false"]
    snapshot = {"fixture": FIXTURE, "session": SESSION, "pid": 42, "truncated": False,
                "lines": [f"pid=42 seq={i} mono={i + 100} {s}" for i, s in enumerate(events, 1)],
                "mono": 120, "input": 1, "native": 1, "valid": True,
                "modelEnabled": True, "modelBusy": False, "modelLoaded": True,
                "controls": [{"native": 1, "on": True, "enabled": True, "attached": True, "registered": True}]}
    request = {"fixture": FIXTURE, "session": SESSION, "originalPassed": True,
               "startedMono": 100, "finishedMono": 115, "mode": "positive"}
    return snapshot, request


class EvidenceTests(unittest.TestCase):
    def test_valid_callback_off_before_later_on(self):
        snapshot, request = example()
        self.assertTrue(capture.validate(snapshot, request, set())["valid"])

    def test_corrupt_or_incomplete_trace_stops(self):
        mutations = [lambda s: s["lines"].pop(4), lambda s: s.update(pid=99),
                     lambda s: s.update(truncated=True), lambda s: s.update(valid=False),
                     lambda s: s.update(fixture=SESSION), lambda s: s.update(mono=110),
                     lambda s: s["controls"][0].update(on=False),
                     lambda s: s["controls"][0].update(registered=False),
                     lambda s: s["controls"].append(copy.deepcopy(s["controls"][0])),
                     lambda s: s["lines"].__setitem__(4, s["lines"][4].replace("on=false", "on=true")),
                     lambda s: s["lines"].__setitem__(1, s["lines"][1].replace("fresh=true", "fresh=false")),
                     lambda s: s["lines"].__setitem__(9, s["lines"][9].replace("valueChanged", "missing")),
                     lambda s: s["lines"].__setitem__(3, s["lines"][3].replace("window-attached", "missing")),
                     lambda s: s["lines"].__setitem__(7, s["lines"][7] + " invalid reason=touch-cancelled")]
        for change in mutations:
            with self.subTest(change=change):
                snapshot, request = example(); change(snapshot)
                with self.assertRaises((AssertionError, KeyError)):
                    capture.validate(snapshot, request, set())

    def test_original_failure_never_becomes_pass(self):
        snapshot, request = example(); request["originalPassed"] = False
        with self.assertRaises(AssertionError): capture.validate(snapshot, request, set())

    def test_duplicate_fixture_rejected(self):
        snapshot, request = example()
        with self.assertRaises(AssertionError): capture.validate(snapshot, request, {FIXTURE})

    def test_no_input_control_is_distinct(self):
        snapshot, request = example(); request["mode"] = "no-input"
        snapshot.update(lines=snapshot["lines"][:4], input=0, valid=False, modelEnabled=False)
        snapshot["controls"][0]["on"] = False
        self.assertTrue(capture.validate(snapshot, request, set())["valid"])
        snapshot["input"] = 1
        with self.assertRaises(AssertionError): capture.validate(snapshot, request, set())

    def test_watchdog_terminates_hung_command(self):
        with tempfile.TemporaryDirectory() as directory:
            started = time.time()
            with self.assertRaises(RuntimeError):
                capture.bounded([sys.executable, "-c", "import time; time.sleep(30)"],
                                time.time() + 1.1, Path(directory) / "log")
            self.assertLess(time.time() - started, 5)

    def test_nonzero_command_not_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(AssertionError):
                capture.bounded([sys.executable, "-c", "raise SystemExit(7)"],
                                time.time() + 3, Path(directory) / "log")


class RunnerTests(unittest.TestCase):
    def exercise(self, behavior):
        # Real mailbox files, fake xcodebuild/app/clock. No simulator or test app.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); out = root / "out"; runner = root / "runner"; app = root / "app"
            clock = [10000.0]; proc = None; mailbox = None; session = None
            state = {"source": {"fake": "immutable"}, "local": False, "jobStarted": clock[0], "device": "fake"}
            if behavior == "budget": state["jobStarted"] -= 50 * 60
            capture.save(out / "state.json", state)
            def configure(_state, _mode, nonce):
                nonlocal mailbox, session
                session = nonce; mailbox = runner / "Documents/DWCapture" / nonce
                mailbox.mkdir(parents=True)
                return root / "fake.xctestrun"
            class Process:
                def __init__(self, *args, **kwargs):
                    nonlocal proc
                    proc = self; self.returncode = None; self.ordinal = 0; self.launched = []
                    self.next()
                def next(self):
                    self.ordinal += 1; self.launched.append(self.ordinal)
                    request = {"ordinal": self.ordinal, "session": session, "fixture": str(uuid.uuid4()).upper(),
                               "mode": "campaign", "startedMono": 100.0}
                    self.request = request
                    capture.save(mailbox / f"start-{self.ordinal}.json", request)
                    if behavior != "missing":
                        capture.save(mailbox / f"request-{self.ordinal}.json",
                                     {**request, "finishedMono": 115.0, "originalPassed": behavior != "failure"})
                def poll(self):
                    if self.returncode is not None: return self.returncode
                    response = mailbox / f"response-{self.ordinal}.json"
                    if response.exists():
                        decision = capture.load(response)["decision"]
                        if decision == "continue" and behavior != "early-exit": self.next()
                        else: self.returncode = 65 if decision == "stop" else 0
                    return self.returncode
                def wait(self, timeout=None): return self.returncode
            def host_command(argv, **kwargs):
                self.assertIn("notify_post", argv)
                snapshot, _ = example(); request = proc.request
                snapshot.update(fixture=request["fixture"], session=session)
                snapshot["lines"][1] = snapshot["lines"][1].replace(FIXTURE, request["fixture"]).replace(SESSION, session)
                if behavior == "stale": snapshot["session"] = SESSION
                capture.save(app / "Library/Caches/DWCapture" / (request["fixture"] + ".json"), snapshot)
                return ""
            def stop(process):
                if process.returncode is None: process.returncode = -15
            with patch.object(capture, "OUT", out), patch.object(capture, "source_guard", return_value=state["source"]), \
                 patch.object(capture, "configure", side_effect=configure), \
                 patch.object(capture, "container", side_effect=lambda _, bundle: runner if bundle == capture.RUNNER else app), \
                 patch.object(capture, "command", side_effect=host_command), patch.object(capture, "inventory", return_value={"verified": True}), \
                 patch.object(capture.subprocess, "Popen", Process), patch.object(capture, "terminate", side_effect=stop), \
                 patch.object(capture.time, "time", side_effect=lambda: clock[0]), \
                 patch.object(capture.time, "sleep", side_effect=lambda seconds: clock.__setitem__(0, clock[0] + seconds)):
                if behavior in ("count", "budget"):
                    capture.run(SimpleNamespace(mode="campaign"))
                else:
                    with self.assertRaises(AssertionError): capture.run(SimpleNamespace(mode="campaign"))
                result = capture.load(out / "campaign/outcome.json")
                with self.assertRaises(FileExistsError): capture.run(SimpleNamespace(mode="campaign"))
                return result, proc.launched

    def test_first_failure_no_next_trial(self):
        result, launched = self.exercise("failure")
        self.assertFalse(result["valid"]); self.assertEqual(launched, [1])

    def test_stale_export_no_next_trial(self):
        result, launched = self.exercise("stale")
        self.assertFalse(result["valid"]); self.assertEqual(launched, [1])

    def test_missing_request_times_out_without_next_trial(self):
        result, launched = self.exercise("missing")
        self.assertIn("watchdog", result["failure"]); self.assertEqual(launched, [1])

    def test_early_zero_exit_after_continue_is_invalid(self):
        result, launched = self.exercise("early-exit")
        self.assertFalse(result["valid"]); self.assertEqual(launched, [1])

    def test_exact_24_cap_and_duplicate_mode_refusal(self):
        result, launched = self.exercise("count")
        self.assertTrue(result["valid"]); self.assertEqual(launched, list(range(1, 25)))
        self.assertEqual(result["completionReason"], "count-limit")

    def test_budget_does_not_admit_next_trial(self):
        result, launched = self.exercise("budget")
        self.assertTrue(result["valid"]); self.assertEqual(launched, [1])
        self.assertEqual(result["completionReason"], "time-admission-limit")


if __name__ == "__main__": unittest.main()
