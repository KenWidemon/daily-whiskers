"""Temporary dispatch-only comparison; never substitute this result for the real CI gate.

Exactly one unchanged lifecycle test per pinned revision, with the identical opt-in
observation patch. No retries, installation of toolchains, state forcing, or fixes.
The official prepare script must find the requested hosted toolchain/runtime.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time

BASELINE = "f513a6d1a7336a9815c5a38f2f6a740d507dabf6"
CANDIDATE = "fe1d25e034bfee7b740344dfa7888be5aa709624"
BRANCH = "codex/stillness-lifecycle-diagnostic"
TEST = "DailyWhiskersUITests/StillnessModeTests/testPersistenceLifecycleCardNavigationAndAuth"
SUBSYSTEM = "com.ken.dailywhiskers.stillness-diagnostic"
APP_ID = "com.example.kenwidemon.dailywhiskers"
TRACE_PATHS = (
    "DailyWhiskers/DailyWhiskersApp.swift", "DailyWhiskers/CISmokeMode.swift",
    "DailyWhiskers/Views/StillnessSettingsView.swift", "DailyWhiskers/StillnessDiagnosticTrace.swift",
    "DailyWhiskersUITests/StillnessModeTests.swift",
)
LOCK = "DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def output(args, cwd=None, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True, stderr=subprocess.PIPE)


def logged(args, log, cwd=None, env=None):
    with log.open("w") as stream:
        return subprocess.run(args, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT).returncode


def exact_test_pass(summary):
    counts = ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")
    if not all(type(summary.get(k)) is int for k in counts):
        return False
    devices = summary.get("devicesAndConfigurations", [])
    if len(devices) != 1 or devices[0].get("passedTests") != 1 or devices[0].get("failedTests") != 0:
        return False
    device = devices[0].get("device", {})
    if device.get("modelName") != "iPhone 17 Pro" or device.get("osVersion") != "26.4.1" or device.get("osBuildNumber") != "23E254a":
        return False
    return (summary.get("result") == "Passed" and summary.get("totalTestCount") == 1
            and summary.get("passedTests") == 1 and summary.get("failedTests") == 0
            and summary.get("skippedTests") == 0 and summary.get("expectedFailures") == 0)


def trace_events(raw, start):
    events = []
    for line in raw.splitlines():
        marker = "DW_STILLNESS_DIAG "
        if marker not in line:
            continue
        try:
            item = json.loads(line.split(marker, 1)[1])
        except (ValueError, TypeError):
            continue
        if isinstance(item, dict) and isinstance(item.get("epoch"), (float, int)) and item["epoch"] >= start:
            events.append(item)
    return events


def trace_coverage(events):
    phases = {x.get("phase") for x in events}
    installs = [x for x in events if x.get("phase") == "trace.install"]
    ids = {x.get("testID") for x in events}
    hooks = bool(installs) and all(x.get("eventHook") is True and x.get("actionHook") is True for x in installs)
    return {
        "events": len(events), "test_domains": len(ids), "hooks_installed": hooks,
        "touch_observed": "touch.beforeDispatch" in phases,
        "native_action_observed": "control.beforeAction" in phases,
        "binding_observed": "binding.before" in phases,
        "preference_observed": "defaults.attached" in phases,
        # Native actions may bypass the hooked base method. Absence is an explicit
        # limitation, not proof of no delivery and not permission to force a pass.
        "minimum_trace_present": hooks and len(ids) == 1 and None not in ids
            and {"touch.beforeDispatch", "binding.before", "defaults.attached"}.issubset(phases),
    }


def pair_pass(records):
    return (set(records) == {"baseline", "candidate"}
            and all(r.get("status") == "completed" and r.get("test_attempts") == 1
                    and r.get("build_exit") == 0 and r.get("test_exit") == 0 and r.get("exact_test_pass") is True
                    and r.get("trace_coverage", {}).get("minimum_trace_present") is True
                    and r.get("video_present") is True and not r.get("collection_errors")
                    for r in records.values()))


def verify_device(device):
    devices = json.loads(output(["xcrun", "simctl", "list", "devices", "available", "--json"]))["devices"]
    matches = [(runtime, item) for runtime, items in devices.items() for item in items if item["udid"] == device]
    if len(matches) != 1:
        raise RuntimeError("Official prepare script did not select exactly one available simulator")
    runtime_id, item = matches[0]
    runtimes = json.loads(output(["xcrun", "simctl", "list", "runtimes", "--json"]))["runtimes"]
    runtime = next(x for x in runtimes if x["identifier"] == runtime_id)
    if (item["deviceTypeIdentifier"] != "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
            or runtime["version"] != "26.4.1" or runtime["buildversion"] != "23E254a"):
        raise RuntimeError("CI model/runtime/build mismatch; no fallback or installation permitted")
    if item["state"] == "Shutdown":
        subprocess.run(["xcrun", "simctl", "boot", device], check=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True)
    return {"model": item["deviceTypeIdentifier"], "runtime": runtime["version"], "build": runtime["buildversion"]}


def collect_artifacts(checkout, derived, artifacts, record, started):
    errors = record.setdefault("collection_errors", [])
    bundle = artifacts / "Lifecycle.xcresult"
    try:
        summary = json.loads(output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)]))
        write_json(artifacts / "test-summary.json", summary)
        record["exact_test_pass"] = exact_test_pass(summary)
        record["test_counts"] = {k: summary.get(k) for k in
                                 ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")}
    except (subprocess.CalledProcessError, ValueError) as error:
        errors.append("Result summary unavailable: " + type(error).__name__)
    try:
        raw = output(["xcrun", "simctl", "spawn", record["device"], "log", "show", "--style", "compact",
                      "--last", "1h", "--info", "--debug", "--predicate", 'subsystem == "' + SUBSYSTEM + '"'])
        (artifacts / "unified-trace.log").write_text(raw)
        events = trace_events(raw, started)
        write_json(artifacts / "trace-events.json", events)
        record["trace_coverage"] = trace_coverage(events)
    except subprocess.CalledProcessError as error:
        errors.append("Unified log collection failed: " + str(error.returncode))
    app = derived / "Build/Products/Debug-iphonesimulator/DailyWhiskers.app"
    try:
        manifest = {str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in app.rglob("*") if p.is_file()}
        write_json(artifacts / "app-sha256.json", manifest)
        info = plistlib.loads((app / "Info.plist").read_bytes())
        record["built_toolchain"] = {k: info.get(k) for k in ("DTXcodeBuild", "DTSDKName", "DTSDKBuild")}
        if info.get("DTXcodeBuild") != "17F113" or info.get("DTSDKName") != "iphonesimulator26.5":
            errors.append("Built app toolchain/SDK mismatch")
    except (OSError, ValueError) as error:
        errors.append("App manifest unavailable: " + type(error).__name__)
    (artifacts / "actual-checkout.diff").write_text(output(["git", "diff", "HEAD"], cwd=checkout))


def run_revision(name, sha, checkout, root, artifacts, packages, expected_device):
    artifacts.mkdir(parents=True)
    record = {"source": sha, "status": "preparing", "test_attempts": 0, "collection_errors": []}
    record_path = artifacts / "observation.json"
    write_json(record_path, record)
    env = os.environ.copy()
    temporary = artifacts.parent / "temporary"
    temporary.mkdir()
    env.update(RUNNER_TEMP=str(temporary), GITHUB_ENV=str(temporary / "prepare.env"))
    try:
        # Reuse the exact approved preparation, including pinned tool checks,
        # synthetic Firebase config, XcodeGen and untouched dependency-lock check.
        code = logged(["python3", "ci/run-stage.py", "prepare", "bash", "ci/prepare-app.sh"],
                      artifacts / "prepare.log", cwd=checkout, env=env)
        if code:
            raise RuntimeError("Official preparation failed: " + str(code))
        device_lines = (temporary / "prepare.env").read_text().splitlines()
        device = next(x.split("=", 1)[1] for x in reversed(device_lines) if x.startswith("SIMULATOR_ID="))
        record["device"] = device
        if expected_device is not None and device != expected_device:
            raise RuntimeError("The pair must use the same official simulator")
        record["environment"] = verify_device(device)
        record["toolchain"] = (checkout / "build/toolchain.txt").read_text()
        # Both revisions receive a fresh synthetic app container. No preferences
        # are set, and the test itself asserts the actual OS motion precondition.
        present = subprocess.run(["xcrun", "simctl", "get_app_container", device, APP_ID, "app"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if present:
            subprocess.run(["xcrun", "simctl", "uninstall", device, APP_ID], check=True)
        derived = artifacts.parent / "derived"
        common = ["-project", "DailyWhiskers.xcodeproj", "-scheme", "DailyWhiskersInteraction",
                  "-configuration", "Debug", "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING",
                  "-destination", "platform=iOS Simulator,id=" + device + ",arch=arm64",
                  "-derivedDataPath", str(derived), "-clonedSourcePackagesDirPath", str(packages),
                  "-onlyUsePackageVersionsFromResolvedFile", "-disableAutomaticPackageResolution",
                  "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO"]
        build = ["xcodebuild", "build-for-testing", *common, "-only-testing:" + TEST]
        record["build_command"] = build
        code = logged(build, artifacts / "build.log", cwd=checkout, env=env)
        record["build_exit"] = code
        if code:
            raise RuntimeError("Build failed; no lifecycle execution started")
        video_log = (artifacts / "video.log").open("w")
        video_path = artifacts / "active-display.mp4"
        video = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(video_path)],
                                 stdout=video_log, stderr=subprocess.STDOUT, start_new_session=True)
        started = time.time()
        test = ["xcodebuild", "test-without-building", *common, "-only-testing:" + TEST,
                "-resultBundlePath", str(artifacts / "Lifecycle.xcresult")]
        record.update(status="running", test_attempts=1, started_epoch=started, test_command=test)
        write_json(record_path, record)
        try:
            record["test_exit"] = logged(test, artifacts / "test.log", cwd=checkout, env=env)
        finally:
            if video.poll() is None:
                try:
                    os.killpg(video.pid, signal.SIGINT)
                except ProcessLookupError:
                    pass
            try:
                record["video_exit"] = video.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(video.pid, signal.SIGKILL)
                video.wait()
                record["collection_errors"].append("Video did not finish on SIGINT")
            video_log.close()
            record["video_present"] = video_path.exists() and video_path.stat().st_size > 0
            collect_artifacts(checkout, derived, artifacts, record, started)
        record["status"] = "completed"
    except (OSError, RuntimeError, subprocess.CalledProcessError, StopIteration, ValueError) as error:
        record["status"] = "error"
        record["error"] = str(error)
    finally:
        write_json(record_path, record)
    return record


def main():
    if (os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
            or os.environ.get("GITHUB_REF_NAME") != BRANCH or os.environ.get("GITHUB_RUN_ATTEMPT") != "1"
            or os.environ.get("GITHUB_REPOSITORY") != "KenWidemon/daily-whiskers"):
        raise SystemExit("Only the first explicitly authorized hosted diagnostic dispatch may execute")
    root = Path(__file__).resolve().parents[1]
    head = output(["git", "rev-parse", "HEAD"], cwd=root).strip()
    if head != os.environ.get("GITHUB_SHA"):
        raise SystemExit("Workflow SHA and checked-out diagnostic revision differ")
    if head != os.environ.get("EXPECTED_DIAGNOSTIC_SHA"):
        raise SystemExit("The dispatch does not match the independently reviewed diagnostic SHA")
    subprocess.run(["git", "merge-base", "--is-ancestor", CANDIDATE, head], cwd=root, check=True)
    artifacts_root = root / "build/stillness-diagnostic"
    artifacts_root.mkdir(parents=True)
    patch = output(["git", "diff", "--binary", CANDIDATE, head, "--", *TRACE_PATHS], cwd=root)
    if not patch.strip():
        raise SystemExit("Missing reviewed diagnostic patch")
    patch_path = artifacts_root / "trace.patch"
    patch_path.write_text(patch)
    patch_hash = hashlib.sha256(patch.encode()).hexdigest()
    source_roots = {}
    applied_hashes = {}
    for name, sha in (("baseline", BASELINE), ("candidate", CANDIDATE)):
        checkout = Path(os.environ["RUNNER_TEMP"]) / ("stillness-diagnostic-" + name)
        subprocess.run(["git", "worktree", "add", "--detach", str(checkout), sha], cwd=root, check=True)
        if (checkout / LOCK).read_bytes() != (root / LOCK).read_bytes():
            raise SystemExit("Dependency lock differs across comparison sources")
        subprocess.run(["git", "apply", "--check", str(patch_path)], cwd=checkout, check=True)
        subprocess.run(["git", "apply", str(patch_path)], cwd=checkout, check=True)
        applied_hashes[name] = {path: hashlib.sha256((checkout / path).read_bytes()).hexdigest() for path in TRACE_PATHS}
        source_roots[name] = checkout
    if applied_hashes["baseline"] != applied_hashes["candidate"]:
        raise SystemExit("Instrumented source seams differ between the two revisions")
    provenance = {"diagnostic_sha": head, "baseline": BASELINE, "candidate": CANDIDATE,
                  "trace_patch_sha256": patch_hash, "scope": "Diagnostic observation only; not CI/release acceptance",
                  "attempt": 1, "applied_trace_source_hashes": applied_hashes,
                  "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    write_json(artifacts_root / "provenance.json", provenance)
    records = {}
    device = None
    cleanup_ok = False
    try:
        for name, sha in (("baseline", BASELINE), ("candidate", CANDIDATE)):
            record = run_revision(name, sha, source_roots[name], root,
                                  artifacts_root / name / "artifacts", root / "build/SourcePackages", device)
            records[name] = record
            device = record.get("device", device)
            write_json(artifacts_root / "observations.json", records)
            # A test assertion failure still gets its paired observation. A setup
            # failure stops rather than substituting an environment or retrying.
            if record["test_attempts"] != 1:
                break
    finally:
        if device:
            cleanup = subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True, text=True)
            state = "unknown"
            try:
                inventory = json.loads(output(["xcrun", "simctl", "list", "devices", "--json"]))["devices"]
                states = [x["state"] for items in inventory.values() for x in items if x["udid"] == device]
                state = states[0] if len(states) == 1 else "unknown"
            except (subprocess.CalledProcessError, ValueError):
                pass
            cleanup_ok = state == "Shutdown"
            write_json(artifacts_root / "cleanup.json", {"shutdown_exit": cleanup.returncode, "verified_state": state,
                       "output": cleanup.stdout, "error": cleanup.stderr})
    passed = pair_pass(records) and cleanup_ok
    summary = ["## Stillness diagnostic observation only", "",
               "This is not PR #127's CI Gate and does not resolve the original failure.",
               "A passing instrumented pair does not establish flakiness or acceptance.", "",
               f"Owned simulator shutdown verified: {cleanup_ok}", "",
               "| Revision | Test exit | Single test passed | Trace present |", "|---|---:|---|---|"]
    for name in ("baseline", "candidate"):
        r = records.get(name, {})
        summary.append(f"| {name} `{r.get('source', 'not run')}` | {r.get('test_exit', 'not run')} | "
                       f"{r.get('exact_test_pass', False)} | {r.get('trace_coverage', {}).get('minimum_trace_present', False)} |")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
        stream.write("\n".join(summary) + "\n")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
