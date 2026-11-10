#!/usr/bin/env python3
"""Bounded, isolated first-enable study. Never acceptance or an automatic retry."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from results import test_counts

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build/capture"
PARENT = "bb7fda49fd3f56398718fabe09b964cce1414c25"
BASE = "32677c90e89725ea6d2811b12cdc80fdfab1cb7e"
HARNESS = "DailyWhiskersUITests/FirstEnableCaptureTests.swift"
APP = "com.example.kenwidemon.dailywhiskers"
RUNNER = "com.ken.DailyWhiskersUITests.xctrunner"
CASE = "FirstEnableCaptureTests/testCapture"
APP_SOURCES = ["DailyWhiskers/DailyWhiskersApp.swift", "DailyWhiskers/Reminders/ReminderModel.swift",
               "DailyWhiskers/Reminders/ReminderSettingsView.swift"]
ALLOWED = set(APP_SOURCES + [HARNESS, "ci/first-enable-capture.py", "ci/test-first-enable-capture.py",
              ".github/workflows/ios.yml", "docs/testing.md", "DailyWhiskers.xcodeproj/project.pbxproj"])


def command(args, timeout=30, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, timeout=timeout, **kwargs).strip()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def load(path):
    return json.loads(path.read_text())


def original_function(text, name):
    start = text.index("    private func " + name + "(")
    end = text.index("\n    }", start) + 6
    return text[start:end]


def audit():
    assert command(["git", "merge-base", "HEAD", PARENT]) == PARENT
    changed = set(command(["git", "diff", "--name-only", PARENT]).splitlines())
    assert changed <= ALLOWED, changed - ALLOWED
    files = command(["git", "ls-tree", "-r", "--name-only", PARENT, "DailyWhiskersUITests"]).splitlines()
    assert set(str(p.relative_to(ROOT)) for p in (ROOT / "DailyWhiskersUITests").rglob("*") if p.is_file()) == set(files + [HARNESS])
    hashes = {}
    for name in files:
        original = subprocess.check_output(["git", "show", f"{PARENT}:{name}"], cwd=ROOT)
        assert (ROOT / name).read_bytes() == original, name
        hashes[name] = hashlib.sha256(original).hexdigest()
    old = (ROOT / "DailyWhiskersUITests/ReminderUITests.swift").read_text()
    new = (ROOT / HARNESS).read_text()
    for name in ["openSettings", "waitEnabled", "waitValue", "tapToggle"]:
        assert original_function(old, name) == original_function(new, name), name
    prefix = old.split("func testPermissionRevocationRegrantAndExplicitDisable() {\n", 1)[1].split("        XCTAssertEqual(app.staticTexts", 1)[0]
    assert original_function(new, "originalPrefix").split("{\n", 1)[1].rsplit("    }", 1)[0] == prefix
    setup = old.split("        app = XCUIApplication()", 1)[1].split("\n    }", 1)[0]
    assert "            app = XCUIApplication()" + setup.replace("\n        ", "\n            ") in new
    for name in APP_SOURCES:
        original = command(["git", "show", f"{BASE}:{name}"])
        stripped = re.sub(r"#if DEBUG && CI_SMOKE_TESTING && DW_SWITCH_OBSERVER\n.*?#endif\n?", "", (ROOT / name).read_text(), flags=re.S)
        assert stripped.rstrip() == original, name
    scheme = ROOT / "DailyWhiskers.xcodeproj/xcshareddata/xcschemes/DailyWhiskersInteraction.xcscheme"
    action = ET.parse(scheme).getroot().find("TestAction")
    assert action is not None and action.find("TestPlans") is None
    assert not command(["git", "ls-files", "*.xctestplan"])
    for node in action.iter():
        assert not any(word in key.lower() for key in node.attrib for word in ("repet", "retry", "iteration"))
    targets = action.findall("Testables/TestableReference")
    assert len(targets) == 1 and targets[0].get("skipped") == "NO" and targets[0].get("parallelizable") == "NO"
    return {"source": command(["git", "rev-parse", "HEAD"]), "parent": PARENT, "original_tests": hashes,
            "candidate_hashes": {f: hashlib.sha256((ROOT / f).read_bytes()).hexdigest() for f in sorted(ALLOWED)},
            "acceptance": False}


def fields(line):
    return dict(re.findall(r"([A-Za-z]+)=([^ ]+)", line))


def validate(snapshot, request, seen):
    """Evidence validity gate, not a root-cause classifier. Raise => stop."""
    for key in ("session", "fixture"):
        assert str(uuid.UUID(request[key])).upper() == request[key]
        assert snapshot[key] == request[key], key
    assert request["fixture"] not in seen, "duplicate fixture"
    assert request["originalPassed"] is True, "original assertion failed"
    assert snapshot["truncated"] is False
    lines = snapshot["lines"]
    assert 1 <= len(lines) < 256
    parsed = [fields(line) for line in lines]
    assert [int(p["seq"]) for p in parsed] == list(range(1, len(lines) + 1)), "trace gap"
    assert all(int(p["pid"]) == snapshot["pid"] for p in parsed), "wrong process"
    assert [float(p["mono"]) for p in parsed] == sorted(float(p["mono"]) for p in parsed)
    assert float(parsed[0]["mono"]) >= request["startedMono"]
    assert snapshot["mono"] >= request["finishedMono"] >= request["startedMono"]
    assert "installed limit=256" in lines[0]
    assert sum("fixture id=" in s for s in lines) == 1
    fixture = next(p for s, p in zip(lines, parsed) if "fixture id=" in s)
    assert fixture["id"] == request["fixture"] and fixture["session"] == request["session"] and fixture["fresh"] == "true"
    assert not any("invalid" in s for s in lines), "invalid observation"
    attached = [(i, p) for i, (s, p) in enumerate(zip(lines, parsed)) if "attached native=" in s and "window-attached" not in s]
    assert len(attached) == 1, "ambiguous control"
    index, entry = attached[0]
    assert entry["registered"] == "true" and entry["on"] == "false"
    controls = snapshot["controls"]
    assert len(controls) == 1 and controls[0]["native"] == int(entry["native"])
    assert controls[0]["attached"] and controls[0]["registered"] and controls[0]["enabled"]
    assert snapshot["modelLoaded"] and not snapshot["modelBusy"]
    if request["mode"] == "no-input":
        assert snapshot["input"] == 0 and not snapshot["modelEnabled"] and not controls[0]["on"]
        assert not any(any(k in s for k in ("before phase=", "valueChanged native=", "binding value=", "command-begin", "command-end")) for s in lines)
        return {"valid": True, "interpretation": "no-enable-input control only"}
    begins = [(i, p) for i, (s, p) in enumerate(zip(lines, parsed)) if "before phase=0 " in s]
    ends = [p for s, p in zip(lines, parsed) if "before phase=3 " in s]
    assert len(begins) == len(ends) == 1
    begin_index, begin = begins[0]
    assert index < begin_index and begin["on"] == "false" and begin["enabled"] == "true" and begin["hidden"] == "false"
    windows = [i for i, s in enumerate(lines) if "window-attached native=" + entry["native"] in s]
    assert len(windows) == 1 and index < windows[0] < begin_index
    assert begin["associatedNative"] == entry["native"] and begin["input"] == "1"
    for p in parsed:
        if "input" in p:
            assert p["valid"] == "true" and p["input"] == "1" and p["associatedNative"] == entry["native"]
    for marker in ["valueChanged native=", "binding value=true", "command-begin", "command-end"]:
        assert sum(marker in s for s in lines) == 1, marker
    assert not any("binding value=false" in s for s in lines)
    end = next(p for s, p in zip(lines, parsed) if "command-end" in s)
    start = next(p for s, p in zip(lines, parsed) if "command-begin" in s)
    assert float(start["mono"]) <= float(end["mono"]) <= request["finishedMono"]
    assert all(float(p["mono"]) <= request["finishedMono"] for p in parsed)
    assert start["value"] == "true" and start["command"] == end["command"] == "1"
    assert end["enabled"] == "true" and end["busy"] == end["error"] == end["storageBlocked"] == "false"
    assert snapshot["valid"] and snapshot["input"] == 1 and snapshot["native"] == int(entry["native"])
    assert snapshot["modelEnabled"] and controls[0]["on"]
    return {"valid": True, "interpretation": "ordinary enable observed; no original failure captured"}


def terminate(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def bounded(args, deadline, log):
    remaining = deadline - time.time()
    assert remaining > 1, "budget exhausted before command"
    with log.open("w") as output:
        process = subprocess.Popen(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            terminate(process)
            raise RuntimeError("bounded command deadline")
    assert code == 0, f"command exit {code}: {log.name}"


def source_guard(local):
    result = audit()
    assert not command(["git", "status", "--porcelain"]), "commit reviewed source before execution"
    assert ALLOWED <= set(command(["git", "ls-files"]).splitlines()), "untracked candidate source"
    if not local:
        assert os.environ.get("GITHUB_RUN_ATTEMPT") == "1"
        assert result["source"] == os.environ["EXPECTED_SOURCE"]
    return result


def prepare(args):
    source = source_guard(args.local)
    OUT.mkdir(parents=True, exist_ok=True)
    marker = OUT / "prepare-started.json"
    with marker.open("x") as stream:
        json.dump({"started": time.time(), "local": args.local}, stream)
    epoch = time.time() if args.local else float(os.environ["CAPTURE_JOB_STARTED"])
    deadline = epoch + 12 * 60
    derived = OUT / "DerivedData"
    packages = Path(args.packages).resolve() if args.packages else OUT / "SourcePackages"
    runtime = args.runtime if args.local else "26.4.1"
    assert runtime
    if not args.local:
        bounded(["bash", "ci/prepare-app.sh"], deadline, OUT / "prepare.log")
    runtimes = json.loads(command(["xcrun", "simctl", "list", "runtimes", "--json"]))["runtimes"]
    matches = [r for r in runtimes if r.get("isAvailable") and r.get("version") == runtime and "iOS" in r["identifier"]]
    assert len(matches) == 1
    name = "DWCapture-" + str(uuid.uuid4())
    device = command(["xcrun", "simctl", "create", name, "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", matches[0]["identifier"]])
    state = {"source": source, "local": args.local, "jobStarted": epoch, "device": device, "name": name,
             "runtime": matches[0], "derived": str(derived), "packages": str(packages), "acceptance": False}
    save(OUT / "state.json", state)  # Persist identity immediately after creation.
    save(OUT / "toolchain.json", {"xcode": command(["xcodebuild", "-version"]), "sdk": command(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"])})
    # Credential-free file, not production Firebase configuration.
    (ROOT / "DailyWhiskers/Resources/GoogleService-Info.plist").write_bytes((ROOT / "ci/firebase-test-config.plist").read_bytes())
    args = ["xcodebuild", "build-for-testing", "-project", "DailyWhiskers.xcodeproj", "-scheme", "DailyWhiskersInteraction",
            "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={device},arch=arm64",
            "-derivedDataPath", str(derived), "-clonedSourcePackagesDirPath", str(packages),
            "-onlyUsePackageVersionsFromResolvedFile", "-disableAutomaticPackageResolution", "CODE_SIGNING_ALLOWED=NO",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING DW_SWITCH_OBSERVER"]
    save(OUT / "build-command.json", args)
    bounded(args, deadline, OUT / "build.log")
    state["prepared"] = time.time()
    save(OUT / "state.json", state)


def configure(state, mode, session):
    products = Path(state["derived"]) / "Build/Products"
    files = [p for p in products.glob("*.xctestrun") if not p.name.startswith("capture-")]
    assert len(files) == 1
    data = plistlib.loads(files[0].read_bytes())
    assert set(data) == {"DailyWhiskersUITests", "__xctestrun_metadata__"}
    target = data["DailyWhiskersUITests"]
    assert target["IsUITestBundle"] and target["TestHostBundleIdentifier"] == RUNNER
    target.setdefault("EnvironmentVariables", {}).update(DW_CAPTURE_SESSION=session, DW_CAPTURE_MODE=mode)
    target["OnlyTestIdentifiers"] = [CASE]
    target["ParallelizationEnabled"] = False
    target["TestTimeoutsEnabled"] = False  # Host enforces bootstrap/trial/total watchdogs.
    file = products / ("capture-" + mode + ".xctestrun")
    file.write_bytes(plistlib.dumps(data))
    return file


def container(device, bundle):
    return Path(command(["xcrun", "simctl", "get_app_container", device, bundle, "data"], timeout=10, stderr=subprocess.DEVNULL))


def inventory(folder, state, deadline):
    bundle = folder / "Capture.xcresult"
    output = {}
    for kind in ("summary", "tests"):
        output[kind] = json.loads(command(["xcrun", "xcresulttool", "get", "test-results", kind,
                                          "--path", str(bundle)], timeout=max(1, min(30, deadline - time.time()))))
        save(folder / (kind + ".json"), output[kind])
    summary = output["summary"]
    counts = test_counts(summary)
    assert counts["totalTestCount"] == counts["executions"] == counts["passedTests"] == 1
    assert counts["failedTests"] == counts["skippedTests"] == counts["expectedFailures"] == 0
    identities = []
    def visit(value):
        if isinstance(value, dict):
            if value.get("nodeType") == "Test Case":
                identities.append(value.get("nodeIdentifier"))
            for child in value.values(): visit(child)
        elif isinstance(value, list):
            for child in value: visit(child)
    visit(output["tests"])
    assert identities == [CASE + "()"], identities
    devices = summary["devicesAndConfigurations"]
    assert len(devices) == 1
    device = devices[0]["device"]
    assert device["deviceId"] == state["device"]
    assert device["modelName"] == "iPhone 17 Pro" and device["architecture"] == "arm64"
    assert device["osVersion"] == state["runtime"]["version"]
    assert device["osBuildNumber"] == state["runtime"]["buildversion"]
    assert device["platform"] == "iOS Simulator"
    return {"counts": counts, "identities": identities, "device": device}


def run(args):
    state = load(OUT / "state.json")
    assert state["source"] == source_guard(state["local"]), "source changed after compilation"
    assert not (state["local"] and args.mode == "campaign"), "local campaign prohibited"
    assert state["local"] or args.mode == "campaign"
    if state["local"] and args.mode == "no-input":
        positive = load(OUT / "positive/outcome.json")
        assert positive["valid"] and positive["exit"] == 0, "positive control must pass first"
    folder = OUT / args.mode
    folder.mkdir(exist_ok=False)  # No rerun, including a failed/partial attempt.
    session = str(uuid.uuid4()).upper()
    config = configure(state, args.mode, session)
    bundle = folder / "Capture.xcresult"
    argv = ["xcodebuild", "test-without-building", "-xctestrun", str(config), "-destination",
            f"platform=iOS Simulator,id={state['device']},arch=arm64", "-parallel-testing-enabled", "NO",
            "-resultBundlePath", str(bundle)]
    save(folder / "command.json", argv)
    save(folder / "identity.json", {"session": session, "source": state["source"], "mode": args.mode})
    started = time.time()
    deadline = min(started + (12 if state["local"] else 40) * 60,
                   started + 12 * 60 if state["local"] else state["jobStarted"] + 52 * 60)
    seen = set()
    completed = []
    active = None
    ordinal = 1
    count = 24 if args.mode == "campaign" else 1
    mailbox = None
    failure = None
    last_progress = started
    completion_reason = None
    with (folder / "test.log").open("w") as output:
        process = subprocess.Popen(argv, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while process.poll() is None:
                now = time.time()
                assert now < deadline, "test phase deadline"
                assert active is None or now - active["hostStarted"] < 180, "trial watchdog"
                assert mailbox is not None or now - started < 360, "runner bootstrap deadline"
                assert active is not None or now - last_progress < (360 if ordinal == 1 else 45), "missing next trial"
                if mailbox is None:
                    try:
                        candidate = container(state["device"], RUNNER) / "Documents/DWCapture" / session
                        if candidate.is_dir():
                            mailbox = candidate
                    except (subprocess.SubprocessError, OSError):
                        pass  # Bounded discovery only; never reruns the test.
                    time.sleep(0.5)
                    continue
                start = mailbox / f"start-{ordinal}.json"
                request_file = mailbox / f"request-{ordinal}.json"
                if active is None and start.is_file():
                    record = load(start)
                    assert ordinal <= count and record["ordinal"] == ordinal and record["session"] == session and record["mode"] == args.mode
                    assert record["fixture"] not in seen
                    active = {**record, "hostStarted": now}
                    last_progress = now
                    save(folder / f"start-{ordinal}.json", active)
                if request_file.is_file():
                    assert active is not None
                    request = load(request_file)
                    for key in ("session", "fixture", "ordinal", "mode", "startedMono"):
                        assert request[key] == active[key], key
                    save(folder / f"request-{ordinal}.json", request)
                    decision = "stop"
                    try:
                        app_container = container(state["device"], APP)
                        evidence = app_container / "Library/Caches/DWCapture" / (request["fixture"] + ".json")
                        assert not evidence.exists(), "stale evidence"
                        command(["xcrun", "simctl", "notify_post", state["device"], "com.dailywhiskers.capture." + session + "." + request["fixture"]], timeout=10)
                        flush_deadline = min(deadline, time.time() + 15)
                        while not evidence.exists() and time.time() < flush_deadline:
                            time.sleep(0.1)
                        snapshot = load(evidence)
                        save(folder / f"observer-{ordinal}.json", snapshot)
                        validity = validate(snapshot, request, seen)
                        decision = "complete" if ordinal == count or deadline - time.time() < 180 else "continue"
                        if decision == "complete":
                            completion_reason = "count-limit" if ordinal == count else "time-admission-limit"
                        completed.append({"ordinal": ordinal, "fixture": request["fixture"], **validity})
                        seen.add(request["fixture"])
                    except (AssertionError, ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
                        failure = f"trial {ordinal}: {type(error).__name__}: {error}"
                    response = {key: request[key] for key in ("session", "fixture", "ordinal", "mode")}
                    response["decision"] = decision
                    target = mailbox / f"response-{ordinal}.json"
                    assert not target.exists(), "duplicate response"
                    save(target, response)
                    save(folder / f"response-{ordinal}.json", response)
                    if decision != "continue":
                        # Allow bounded XCTest finalization, never another trial.
                        while process.poll() is None and time.time() < min(deadline, now + 90):
                            assert not (mailbox / f"start-{ordinal + 1}.json").exists(), "trial after stop"
                            time.sleep(0.2)
                        if process.poll() is None:
                            raise RuntimeError("test finalization deadline")
                        break
                    ordinal += 1
                    active = None
                    last_progress = time.time()
                time.sleep(0.1)
        except (AssertionError, ValueError, KeyError, TypeError, OSError, RuntimeError, subprocess.SubprocessError) as error:
            failure = failure or f"{type(error).__name__}: {error}"
        finally:
            terminate(process)
            code = process.returncode
    result = {"valid": failure is None and code == 0 and len(completed) >= 1 and completion_reason is not None,
              "exit": code,
              "failure": failure, "trials": completed, "session": session, "elapsed": time.time() - started,
              "completionReason": completion_reason,
              "acceptance": False, "interpretation": "Stop and inspect; passing trials do not resolve original failures"}
    if result["valid"]:
        try:
            result["inventory"] = inventory(folder, state, deadline)
        except (AssertionError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
            result["valid"] = False
            result["failure"] = "raw inventory: " + str(error)
    save(folder / "outcome.json", result)
    assert result["valid"], result


def collect():
    deadline = time.time() + 270
    for folder in [OUT / mode for mode in ("positive", "no-input", "campaign")]:
        bundle = folder / "Capture.xcresult"
        if not bundle.exists():
            continue
        for name, argv in [("summary", ["get", "test-results", "summary"]), ("tests", ["get", "test-results", "tests"]),
                           ("activities", ["get", "test-results", "activities", "--test-id", CASE + "()"]),
                           ("diagnostics", ["export", "diagnostics", "--output-path", str(folder / "diagnostics")]),
                           ("attachments", ["export", "attachments", "--output-path", str(folder / "attachments")])]:
            try:
                bounded(["xcrun", "xcresulttool"] + argv + ["--path", str(bundle)], deadline, folder / (name + ".json"))
            except (AssertionError, RuntimeError, subprocess.SubprocessError) as error:
                save(folder / (name + "-error.json"), {"error": str(error), "acceptance": False})


def cleanup():
    state = load(OUT / "state.json")
    devices = json.loads(command(["xcrun", "simctl", "list", "devices", "--json"]))["devices"]
    found = [d for group in devices.values() for d in group if d["udid"] == state["device"]]
    assert len(found) == 1 and found[0]["name"] == state["name"] and state["name"].startswith("DWCapture-")
    if found[0]["state"] != "Shutdown":
        command(["xcrun", "simctl", "shutdown", state["device"]])
    command(["xcrun", "simctl", "delete", state["device"]])
    remaining = json.loads(command(["xcrun", "simctl", "list", "devices", "--json"]))["devices"]
    assert not any(d["udid"] == state["device"] for group in remaining.values() for d in group)
    save(OUT / "cleanup.json", {"deleted": state["device"], "name": state["name"], "verified": True})


if __name__ == "__main__":
    os.chdir(ROOT)
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["audit", "prepare", "run", "collect", "cleanup"])
    parser.add_argument("--local", action="store_true")
    parser.add_argument("--runtime")
    parser.add_argument("--packages")
    parser.add_argument("--mode", choices=["positive", "no-input", "campaign"])
    args = parser.parse_args()
    if args.action == "audit":
        print(json.dumps(audit(), indent=2))
    elif args.action == "prepare":
        prepare(args)
    elif args.action == "run":
        assert args.mode
        run(args)
    else:
        {"collect": collect, "cleanup": cleanup}[args.action]()
