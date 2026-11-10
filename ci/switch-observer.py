#!/usr/bin/env python3
"""One isolated diagnostic attempt; never a release/acceptance runner."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

from results import test_counts

BASE = "32677c90e89725ea6d2811b12cdc80fdfab1cb7e"
CASES = [
    "ReminderUITests/testDeniedTimeEditKeepsEnabledIntentAndExplainsMissingCoverage",
    "ReminderUITests/testPermissionRevocationRegrantAndExplicitDisable",
]
ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
BUNDLE = BUILD / "Observer.xcresult"
SOURCES = ["DailyWhiskers/DailyWhiskersApp.swift",
           "DailyWhiskers/Reminders/ReminderSettingsView.swift",
           "DailyWhiskers/Reminders/ReminderModel.swift"]


def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def save(name, value):
    BUILD.mkdir(exist_ok=True)
    (BUILD / name).write_text(json.dumps(value, indent=2) + "\n")


def audit():
    assert output("git", "merge-base", "HEAD", BASE) == BASE
    changed = set(output("git", "diff", "--name-only", BASE).splitlines())
    assert changed <= set(SOURCES + [".github/workflows/ios.yml", "ci/switch-observer.py", "docs/testing.md"]), changed
    files = output("git", "ls-tree", "-r", "--name-only", BASE, "DailyWhiskersUITests").splitlines()
    assert sorted(str(p.relative_to(ROOT)) for p in (ROOT / "DailyWhiskersUITests").rglob("*") if p.is_file()) == sorted(files)
    # With no repetition CLI options, use the audited scheme's single-run defaults.
    scheme = ROOT / "DailyWhiskers.xcodeproj/xcshareddata/xcschemes/DailyWhiskersInteraction.xcscheme"
    action = ET.parse(scheme).getroot().find("TestAction")
    assert action is not None and action.find("TestPlans") is None
    assert not output("git", "ls-files", "*.xctestplan")
    for node in action.iter():
        assert not any(word in key.lower() for key in node.attrib
                       for word in ("repet", "retry", "iteration")), "Unexpected repetition setting"
    testables = action.findall("Testables/TestableReference")
    assert len(testables) == 1 and testables[0].get("skipped") == "NO"
    assert testables[0].get("parallelizable") == "NO"
    assert testables[0].find("BuildableReference").get("BlueprintName") == "DailyWhiskersUITests"
    hashes = {}
    for filename in files:
        expected = subprocess.check_output(["git", "show", f"{BASE}:{filename}"], cwd=ROOT)
        actual = (ROOT / filename).read_bytes()
        assert actual == expected, f"Original test bytes changed: {filename}"
        hashes[filename] = hashlib.sha256(actual).hexdigest()
    # The opt-in blocks must be the ONLY differences in application source.
    for filename in SOURCES:
        original = output("git", "show", f"{BASE}:{filename}")
        stripped = re.sub(r"#if DEBUG && CI_SMOKE_TESTING && DW_SWITCH_OBSERVER\n.*?#endif\n?",
                          "", (ROOT / filename).read_text(), flags=re.S)
        assert stripped.rstrip() == original, f"Non-diagnostic source change: {filename}"
    save("observer-source.json", {
        "base": BASE, "source": output("git", "rev-parse", "HEAD"),
        "test_sha256": hashes, "cases": CASES, "run": os.getenv("GITHUB_RUN_ID"),
        "scheme_sha256": hashlib.sha256(scheme.read_bytes()).hexdigest(),
        "repetition": "Scheme default; no test plan or repetition/retry override",
        "attempt": os.getenv("GITHUB_RUN_ATTEMPT"), "acceptance": False,
    })
    print("Original test bytes and application behavior outside opt-in blocks verified.")


def simulator():
    runtimes = json.loads(output("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    matches = [r for r in runtimes if r.get("isAvailable") and r.get("version") == "26.4.1"
               and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    assert len(matches) == 1
    name = "DWObserver-" + os.environ["GITHUB_RUN_ID"]
    identifier = output("xcrun", "simctl", "create", name,
                        "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", matches[0]["identifier"])
    save("observer-simulator.json", {"id": identifier, "name": name, "runtime": matches[0]})
    with open(os.environ["GITHUB_ENV"], "a") as stream:
        stream.write(f"SIMULATOR_ID={identifier}\n")


def execute(stage):
    audit()
    assert os.environ["GITHUB_RUN_ATTEMPT"] == "1"
    assert output("git", "rev-parse", "HEAD") == os.environ["EXPECTED_SOURCE"]
    marker = BUILD / f"observer-{stage}-started.json"
    # Refuse a second invocation within the attempt, including after failure.
    with marker.open("x") as stream:
        json.dump({"started": time.time(), "cases": CASES}, stream)
    common = ["-project", "DailyWhiskers.xcodeproj", "-scheme", "DailyWhiskersInteraction",
              "-configuration", "Debug", "-destination",
              f"platform=iOS Simulator,id={os.environ['SIMULATOR_ID']},arch=arm64",
              "-derivedDataPath", "build/ObserverDerivedData", "-clonedSourcePackagesDirPath",
              "build/SourcePackages", "-onlyUsePackageVersionsFromResolvedFile",
              "-disableAutomaticPackageResolution", "CODE_SIGNING_ALLOWED=NO",
              "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING DW_SWITCH_OBSERVER"]
    args = ["xcodebuild", "build-for-testing" if stage == "build" else "test-without-building"] + common
    if stage == "test":
        args += ["-parallel-testing-enabled", "NO",
                 "-resultBundlePath", str(BUNDLE)]
        args += ["-only-testing:DailyWhiskersUITests/" + case for case in CASES]
    save(f"observer-{stage}-command.json", args)
    with (BUILD / f"observer-{stage}.log").open("w") as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    save(f"observer-{stage}-exit.json", {"exit_code": result.returncode})
    raise SystemExit(result.returncode)


def collect():
    BUILD.mkdir(exist_ok=True)
    errors = []
    deadline = time.monotonic() + 270  # Leaves 30s within the five-minute step.
    commands = [
        ("summary", ["get", "test-results", "summary", "--path", str(BUNDLE)]),
        ("tests", ["get", "test-results", "tests", "--path", str(BUNDLE)]),
        *[(f"activity-{index}", ["get", "test-results", "activities", "--path", str(BUNDLE),
                                  "--test-id", case + "()"])
          for index, case in enumerate(CASES)],
        ("diagnostics", ["export", "diagnostics", "--path", str(BUNDLE),
                         "--output-path", str(BUILD / "observer-diagnostics")]),
        ("attachments", ["export", "attachments", "--path", str(BUNDLE),
                         "--output-path", str(BUILD / "observer-attachments")]),
    ]
    for name, args in commands:
        suffix = ".json" if name in {"summary", "tests"} or name.startswith("activity-") else ".log"
        try:
            with (BUILD / ("observer-" + name + suffix)).open("w") as stream:
                subprocess.run(["xcrun", "xcresulttool"] + args, stdout=stream,
                               stderr=subprocess.STDOUT, check=True,
                               timeout=max(1, min(100, deadline - time.monotonic())))
        except (subprocess.SubprocessError, OSError) as error:
            errors.append({"stage": name, "error": type(error).__name__})
    # xcresult app stdout survives even when Xcode has already shut down its clone.
    traces = []
    for file in (BUILD / "observer-diagnostics").rglob("StandardOutputAndStandardError-*.txt"):
        for line in file.read_text(errors="replace").splitlines():
            if "[DWSwitchObserver]" in line:
                traces.append(line)
    (BUILD / "observer-trace.log").write_text("\n".join(traces) + "\n")
    executed = []
    counts = None
    runtime = None
    def visit(value):
        if isinstance(value, dict):
            if value.get("nodeType") == "Test Case":
                executed.append({"id": value.get("nodeIdentifier"), "result": value.get("result")})
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    try:
        visit(json.loads((BUILD / "observer-tests.json").read_text()))
        assert sorted(item["id"] for item in executed) == sorted(case + "()" for case in CASES)
        summary = json.loads((BUILD / "observer-summary.json").read_text())
        counts = test_counts(summary)
        assert counts["totalTestCount"] == counts["executions"] == 2
        assert counts["skippedTests"] == counts["expectedFailures"] == 0
        assert counts["passedTests"] + counts["failedTests"] == 2
        configurations = summary["devicesAndConfigurations"]
        assert len(configurations) == 1
        runtime = configurations[0]["device"]
        assert runtime["modelName"] == "iPhone 17 Pro"
        assert runtime["osVersion"] == "26.4.1" and runtime["architecture"] == "arm64"
        assert runtime["osBuildNumber"] == "23E254a"
        assert runtime["platform"] == "iOS Simulator"
    except (ValueError, OSError, AssertionError, TypeError, KeyError):
        errors.append({"stage": "inventory", "error": "Missing/duplicate/unexpected cases"})
    if not traces:
        errors.append({"stage": "trace", "error": "No retained observer stdout"})
    save("observer-evidence.json", {"cases": executed, "collection_errors": errors,
                                    "counts": counts, "runtime": runtime,
                                    "trace_lines": len(traces), "acceptance": False,
                                    "interpretation": "Manual initial-enable positive-control review required"})
    if errors:
        raise SystemExit("Diagnostic evidence incomplete; stop as inconclusive.")


def cleanup():
    path = BUILD / "observer-simulator.json"
    if not path.is_file():
        return
    saved = json.loads(path.read_text())
    assert saved["name"] == "DWObserver-" + os.environ["GITHUB_RUN_ID"]
    devices = json.loads(output("xcrun", "simctl", "list", "devices", "--json"))["devices"]
    found = [d for group in devices.values() for d in group if d["udid"] == saved["id"]]
    if not found:
        return
    assert len(found) == 1 and found[0]["name"] == saved["name"]
    subprocess.run(["xcrun", "simctl", "shutdown", saved["id"]], timeout=30, check=False)
    subprocess.run(["xcrun", "simctl", "delete", saved["id"]], timeout=30, check=True)


if __name__ == "__main__":
    os.chdir(ROOT)
    action = sys.argv[1]
    if action in {"build", "test"}:
        execute(action)
    else:
        {"audit": audit, "simulator": simulator, "collect": collect, "cleanup": cleanup}[action]()
