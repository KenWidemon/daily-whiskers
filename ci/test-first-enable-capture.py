"""Hermetic evidence rejection and watchdog checks; no app execution."""
import copy
import importlib.util
from pathlib import Path
import sys
import tempfile
import time
import unittest

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


if __name__ == "__main__": unittest.main()
