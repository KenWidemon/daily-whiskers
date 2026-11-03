"""One candidate suite-context observation, never a replacement for PR127 CI.

Reuse official prepare/resolve/unit/UI commands. Preserve the original 20-test
order as an evidence requirement; no retries, selective reruns or forced state.
The previous paired runner remains unchanged as historical guard implementation.
"""
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location("previous", Path(__file__).with_name("stillness-diagnostic.py"))
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
CANDIDATE = previous.CANDIDATE
BRANCH = previous.BRANCH
TRACE_PATHS = previous.TRACE_PATHS
LOCK = previous.LOCK
UI_PATTERN = r"Test Case '-\[DailyWhiskersUITests\.(\w+) (\w+)\]' started\."


def suite_order(log, expected):
    actual = ["/".join(x) for x in re.findall(UI_PATTERN, log)]
    return {"actual": actual, "expected": expected, "exact": actual == expected,
            "duplicates": len(actual) != len(set(actual))}


def suite_pass(summary, count, expanded_count=None):
    expanded_count = count if expanded_count is None else expanded_count
    for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"):
        if type(summary.get(key)) is not int:
            return False
    configs = summary.get("devicesAndConfigurations", [])
    if len(configs) != 1:
        return False
    device = configs[0].get("device", {})
    return (summary.get("result") == "Passed" and summary["totalTestCount"] == count
            and summary["passedTests"] == count and summary["failedTests"] == 0
            and summary["skippedTests"] == 0 and summary["expectedFailures"] == 0
            and configs[0].get("passedTests") == expanded_count and configs[0].get("failedTests") == 0
            and device.get("modelName") == "iPhone 17 Pro"
            and device.get("osVersion") == "26.4.1" and device.get("osBuildNumber") == "23E254a")


def trace_controls(events):
    basic = previous.trace_coverage(events)
    # Logs are chronological at collection, but validate each process separately.
    # Sequence gaps reject completeness; a final missing tail is still unknowable.
    processes = {}
    for event in events:
        processes.setdefault(event.get("pid"), []).append(event)
    sequence_ok = bool(processes) and None not in processes
    for process in processes.values():
        seq = [e.get("sequence") for e in process]
        sequence_ok &= all(type(x) is int for x in seq) and seq == list(range(1, len(seq) + 1))
        sequence_ok &= process[0].get("phase") == "trace.install"
        sequence_ok &= all(e.get("mainThread") is True for e in process)
    before = [e for e in events if e.get("phase") == "binding.before"]
    after = [e for e in events if e.get("phase") == "binding.after"]
    # The first enable and disable precede the failing second enable. Require
    # action/touch/state evidence for those real positive controls, not only a
    # nonempty trace. Do not demand success of the interaction being investigated.
    controls = len(before) >= 2 and len(after) >= 2
    if controls:
        controls = ([e.get("requested") for e in before[:2]] == [True, False]
                    and [e.get("stored") for e in after[:2]] == [True, False])
        for b, a in zip(before[:2], after[:2]):
            controls &= b.get("pid") == a.get("pid") and b["epoch"] <= a["epoch"]
            controls &= any(e.get("pid") == b.get("pid") and e.get("phase") == "control.beforeAction"
                            and 0 <= b["epoch"] - e["epoch"] < 2 for e in events)
            controls &= any(e.get("pid") == b.get("pid") and e.get("phase") == "touch.beforeDispatch"
                            and 0 <= b["epoch"] - e["epoch"] < 2 for e in events)
            controls &= any(e.get("pid") == a.get("pid") and e.get("phase") == "appStorage.change"
                            and e.get("new") == a.get("stored") and 0 <= e["epoch"] - a["epoch"] < 5
                            for e in events)
    return {**basic, "sequence_complete_to_last_observed_event": bool(sequence_ok),
            "earlier_enable_disable_controls": bool(controls),
            "interpretable_controls": basic["minimum_trace_present"] and bool(sequence_ok) and bool(controls),
            "limit": "Hooks/logging perturb timing; sequence checks cannot prove an uncaptured final tail. Defaults notifications are not a complete write timeline."}


def observation_pass(record, cleaned):
    return (cleaned and record.get("status") == "completed" and record.get("ui_attempts") == 1
            and all(record.get("stages", {}).get(s) == 0 for s in ("prepare", "resolve", "unit", "ui"))
            and record.get("unit_exact_pass") is True and record.get("ui_exact_pass") is True
            and record.get("order", {}).get("exact") is True
            and record.get("trace_controls", {}).get("interpretable_controls") is True
            and record.get("video_valid") is True and not record.get("collection_errors"))


def stage(checkout, env, name, command, artifacts, record, deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise RuntimeError("One-hour execution budget exhausted; no next stage")
    args = ["python3", "ci/run-stage.py", name, *command]
    record.setdefault("commands", {})[name] = args
    with (artifacts / (name + "-console.log")).open("w") as log:
        child = subprocess.Popen(args, cwd=checkout, env=env, stdout=log,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = child.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            record["stages"][name] = "timed_out"
            raise RuntimeError("Execution budget exhausted during " + name)
    record["stages"][name] = code
    return code


def collect(checkout, root, artifacts, record, started):
    errors = record["collection_errors"]
    for name, bundle, count, expanded in (("unit", "TestResults.xcresult", 143, 206), ("ui", "SmokeResults.xcresult", 20, 20)):
        try:
            data = json.loads(previous.output(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                              "--path", str(checkout / "build" / bundle)]))
            previous.write_json(artifacts / (name + "-summary.json"), data)
            record[name + "_exact_pass"] = suite_pass(data, count, expanded)
        except (subprocess.CalledProcessError, ValueError) as error:
            errors.append(name + " summary unavailable: " + str(error))
    expected = json.loads((root / "ci/stillness-suite-order.json").read_text())["tests"]
    log_path = checkout / "build/ui.log"
    record["order"] = suite_order(log_path.read_text() if log_path.exists() else "", expected)
    if not record["order"]["exact"]:
        errors.append("Actual test order differs from original 20-case suite; no equivalent-context claim")
    if started is not None:
        try:
            raw = previous.output(["xcrun", "simctl", "spawn", record["device"], "log", "show",
                                   "--style", "compact", "--last", "2h", "--info", "--debug",
                                   "--predicate", 'subsystem == "' + previous.SUBSYSTEM + '"'])
            (artifacts / "unified-trace.log").write_text(raw)
            events = previous.trace_events(raw, started)
            previous.write_json(artifacts / "trace-events.json", events)
            record["trace_controls"] = trace_controls(events)
        except (subprocess.CalledProcessError, ValueError, KeyError, TypeError) as error:
            errors.append("Trace collection/validation failed: " + str(error))
    # Preserve original bundles and logs, including failed/partial ones. Do not
    # run the canonical CI collector and misrepresent this as release validation.
    for path in (checkout / "build").iterdir():
        if path.name in ("TestResults.xcresult", "SmokeResults.xcresult"):
            shutil.copytree(path, artifacts / path.name)
        elif path.is_file() and (path.suffix in (".log", ".json", ".txt")):
            shutil.copy2(path, artifacts / path.name)
    app = checkout / "build/SmokeDerivedData/Build/Products/Debug-iphonesimulator/DailyWhiskers.app"
    if app.exists():
        import plistlib
        info = plistlib.loads((app / "Info.plist").read_bytes())
        record["built_toolchain"] = {k: info.get(k) for k in ("DTXcodeBuild", "DTSDKName", "DTSDKBuild")}
        if record["built_toolchain"] != {"DTXcodeBuild": "17F113", "DTSDKName": "iphonesimulator26.5", "DTSDKBuild": "23F81a"}:
            errors.append("Built toolchain/SDK mismatch")
        previous.write_json(artifacts / "app-sha256.json", {
            str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in app.rglob("*") if p.is_file()})
    else:
        errors.append("UI application artifact unavailable")
    (artifacts / "actual-checkout.diff").write_text(previous.output(["git", "diff", "HEAD"], cwd=checkout))


def observe(checkout, root, artifacts):
    artifacts.mkdir(parents=True)
    record = {"source": CANDIDATE, "status": "preparing", "ui_attempts": 0,
              "stages": {}, "collection_errors": []}
    owner, started, cleaned = {}, None, False
    env = os.environ.copy()
    temporary = artifacts.parent / "temporary"
    temporary.mkdir()
    env.update(RUNNER_TEMP=str(temporary), GITHUB_ENV=str(temporary / "prepare.env"),
               GITHUB_WORKSPACE=str(checkout))
    deadline = time.monotonic() + 3600  # Process budget, never an XCTest assertion change.
    try:
        if stage(checkout, env, "prepare", ["bash", "ci/prepare-app.sh"], artifacts, record, deadline):
            raise RuntimeError("Official preparation failed; no fallback")
        lines = (temporary / "prepare.env").read_text().splitlines()
        device = next(x.split("=", 1)[1] for x in reversed(lines) if x.startswith("SIMULATOR_ID="))
        environment = previous.verify_device(device)
        # Record only the verified owned hosted selection before xcodebuild may
        # boot it. Preserve official unit-stage boot/app state; no extra reset.
        owner.update(device=device, environment=environment)
        previous.write_json(artifacts.parent / "ownership.json", owner)
        record.update(device=device, environment=environment)
        env["SIMULATOR_ID"] = device
        if stage(checkout, env, "resolve", ["bash", "ci/test-app.sh", "resolve"], artifacts, record, deadline):
            raise RuntimeError("Resolve failed; stop before tests")
        if stage(checkout, env, "unit", ["bash", "ci/test-app.sh", "unit"], artifacts, record, deadline):
            raise RuntimeError("Unit preconditioning failed; stop without new UI attempt")
        unit = json.loads(previous.output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path",
                                           str(checkout / "build/TestResults.xcresult")]))
        previous.write_json(artifacts / "precondition-unit-summary.json", unit)
        # Original summary has 143 tests and 206 parameter-expanded device runs.
        record["unit_exact_pass"] = suite_pass(unit, 143, 206)
        if not record["unit_exact_pass"]:
            raise RuntimeError("Unit counts/environment differ from original preconditioning; no UI attempt")
        previous.write_json(artifacts / "post-unit-device.json", previous.verify_device(device))
        video_path, video_log_path = artifacts / "active-display.mp4", artifacts / "video.log"
        timing = {"spawn_epoch": time.time(), "spawn_monotonic": time.monotonic()}
        record["recorder"] = timing
        with video_log_path.open("w") as video_log:
            video = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(video_path)],
                                     stdout=video_log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                previous.wait_recorder_ready(video, video_log_path, timing)
                started = time.time()
                timing["test_start_monotonic"] = time.monotonic()
                record.update(status="running", ui_attempts=1, started_epoch=started)
                previous.write_json(artifacts / "observation.json", record)
                try:
                    stage(checkout, env, "ui", ["bash", "ci/test-app.sh", "ui"], artifacts, record, deadline)
                finally:
                    timing.update(test_end_epoch=time.time(), test_end_monotonic=time.monotonic())
                time.sleep(1)  # Unchanged capture postroll; no test wait or guard relaxation.
            finally:
                previous.stop_recorder(video, timing, record["collection_errors"])
                video_log.flush()
                record["video_present"] = video_path.exists() and video_path.stat().st_size > 0
                previous.validate_recording(root, artifacts, record)
        record["status"] = "completed"
    except (OSError, RuntimeError, subprocess.CalledProcessError, StopIteration, ValueError) as error:
        record.update(status="error", error=str(error))
    finally:
        try:
            collect(checkout, root, artifacts, record, started)
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            record["collection_errors"].append("Artifact collection incomplete: " + str(error))
        finally:
            try:
                cleaned = previous.cleanup_owned(owner, artifacts.parent)
            finally:
                previous.write_json(artifacts / "observation.json", record)
    return record, cleaned


def main():
    if (os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
            or os.environ.get("GITHUB_REF_NAME") != BRANCH or os.environ.get("GITHUB_RUN_ATTEMPT") != "1"
            or os.environ.get("GITHUB_REPOSITORY") != "KenWidemon/daily-whiskers"):
        raise SystemExit("Only the single approved first hosted dispatch can execute")
    root = Path(__file__).resolve().parents[1]
    head = previous.output(["git", "rev-parse", "HEAD"], cwd=root).strip()
    if head != os.environ.get("GITHUB_SHA") or head != os.environ.get("EXPECTED_DIAGNOSTIC_SHA"):
        raise SystemExit("Diagnostic head does not match independently reviewed dispatch SHA")
    subprocess.run(["git", "merge-base", "--is-ancestor", CANDIDATE, head], cwd=root, check=True)
    artifacts_root = root / "build/stillness-suite-diagnostic"
    artifacts_root.mkdir(parents=True)  # Existing output is a hard stop, not a repeat.
    patch = previous.output(["git", "diff", "--binary", CANDIDATE, head, "--", *TRACE_PATHS], cwd=root)
    if not patch.strip():
        raise SystemExit("Missing diagnostic patch")
    patch_path = artifacts_root / "trace.patch"
    patch_path.write_text(patch)
    checkout = Path(os.environ["RUNNER_TEMP"]) / "stillness-suite-candidate"
    subprocess.run(["git", "worktree", "add", "--detach", str(checkout), CANDIDATE], cwd=root, check=True)
    if (checkout / LOCK).read_bytes() != (root / LOCK).read_bytes():
        raise SystemExit("Dependency lock mismatch")
    subprocess.run(["git", "apply", "--check", str(patch_path)], cwd=checkout, check=True)
    subprocess.run(["git", "apply", str(patch_path)], cwd=checkout, check=True)
    test_path = "DailyWhiskersUITests/StillnessModeTests.swift"
    original_test = previous.output(["git", "show", CANDIDATE + ":" + test_path], cwd=root)
    anchor = '        app.launchEnvironment["DW_STILLNESS_TEST_ID"] = UUID().uuidString'
    opt_in = '\n        if name.contains("testPersistenceLifecycleCardNavigationAndAuth") {\n' \
             '            app.launchEnvironment["DW_STILLNESS_DIAGNOSTICS"] = "1"\n        }'
    if original_test.count(anchor) != 1 or (checkout / test_path).read_text() != original_test.replace(anchor, anchor + opt_in):
        raise SystemExit("Lifecycle source changed beyond passive opt-in; no execution")
    # Official command retains GITHUB_WORKSPACE/build/SourcePackages. Share only
    # the restored dependency cache, never derived data or a prior app container.
    (checkout / "build").mkdir()
    (root / "build/SourcePackages").mkdir(exist_ok=True)
    (checkout / "build/SourcePackages").symlink_to(root / "build/SourcePackages", target_is_directory=True)
    provenance = {"diagnostic_sha": head, "candidate": CANDIDATE, "attempt": 1,
                  "scope": "One original suite-context observation; not PR127 gate or product acceptance",
                  "trace_patch_sha256": hashlib.sha256(patch.encode()).hexdigest(),
                  "trace_source_hashes": {p: hashlib.sha256((checkout / p).read_bytes()).hexdigest() for p in TRACE_PATHS},
                  "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    previous.write_json(artifacts_root / "provenance.json", provenance)
    record, cleaned = observe(checkout, root, artifacts_root / "artifacts")
    passed = observation_pass(record, cleaned)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write("## Stillness suite-context diagnostic only\n\n"
                      "One attempt; no rerun. A pass is nonreproduction, not resolution or acceptance.\n\n"
                      + f"Candidate: `{CANDIDATE}`; UI exit: {record['stages'].get('ui', 'not run')}; "
                      + f"exact original order: {record.get('order', {}).get('exact', False)}; "
                      + f"recording valid: {record.get('video_valid', False)}; owned cleanup: {cleaned}.\n")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
