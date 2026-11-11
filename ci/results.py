"""Result-bundle evidence, including XCTest and Swift Testing, without log-count guesses."""
import argparse
import html
import json
import os
from pathlib import Path
import subprocess
import sys
from simulator import BUILD, NAME, VERSION

SUITES = {"unit": "TestResults.xcresult", "ui": "SmokeResults.xcresult"}
STAGES = ("prepare", "resolve", "unit", "ui", "release")


def test_counts(summary):
    keys = ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")
    if any(type(summary.get(key)) is not int or summary[key] < 0 for key in keys):
        raise ValueError("Missing or invalid test counts")
    counts = {key: summary[key] for key in keys}
    if counts["totalTestCount"] != sum(counts[k] for k in keys[1:]):
        raise ValueError("Inconsistent test counts")
    # Top-level counts are test cases across BOTH frameworks. Per-device counts
    # include dynamic-parameter executions; do not add these to test case counts.
    devices = summary.get("devicesAndConfigurations", [])
    counts["devices"] = devices
    counts["executions"] = None
    run_keys = ("passedTests", "failedTests", "skippedTests", "expectedFailures")
    if devices and all(type(d.get(k)) is int and d[k] >= 0 for d in devices for k in run_keys):
        counts["executions"] = sum(d[k] for d in devices for k in run_keys)
    counts["result"] = summary.get("result", "unknown")
    counts["valid_pass"] = (counts["totalTestCount"] > 0 and counts["result"] == "Passed"
                            and counts["failedTests"] == 0 and counts["skippedTests"] == 0
                            and counts["expectedFailures"] == 0)
    return counts


def collect(directory, part=None):
    from ui_shards import annotate, stages_for
    stages = stages_for(part) if part else STAGES
    suites = ({"unit": SUITES["unit"]} if part == "unit-release" else
              {"ui": f"SmokeResults-{part}.xcresult"}) if part else SUITES
    records = {}
    for stage in stages:
        path = directory / f"{stage}-status.json"
        records[stage] = json.loads(path.read_text()) if path.exists() else {"status": "not run"}
    for stage, bundle in suites.items():
        record = records[stage]
        if not (directory / bundle).exists():
            record["results_error"] = "No result bundle; counts unavailable"
            continue
        try:
            raw = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                           "--path", str(directory / bundle)], text=True, stderr=subprocess.PIPE,
                                          timeout=45)
            (directory / f"{stage}-results.json").write_text(raw)
            record["tests"] = test_counts(json.loads(raw))
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            record["results_error"] = f"Unreadable result bundle ({type(error).__name__}); counts unavailable"
    valid = all(records[s]["status"] == "success" for s in stages) and all(
        records[s].get("tests", {}).get("valid_pass", False) for s in suites)
    output = {"stages": records, "verified": valid}
    if part:
        try:
            tree = None
            if part != "unit-release":
                raw = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "tests",
                                               "--path", str(directory / suites["ui"])], text=True, stderr=subprocess.PIPE,
                                              timeout=45)
                (directory / "ui-test-tree.json").write_text(raw)
                tree = json.loads(raw)
            annotate(output, directory, part, tree)
        except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as error:
            output["evidence_error"] = str(error)
            valid = False
        output["verified"] = valid
    (directory / "results.json").write_text(json.dumps(output, indent=2))
    return valid


def safe(value):
    return html.escape(str(value)).replace("|", "&#124;").replace("\n", "<br>")


def identity():
    env = os.environ
    return [f"Source SHA: `{safe(env.get('SOURCE_SHA', 'unavailable'))}`",
            f"Tested checkout SHA: `{safe(env.get('TESTED_SHA', 'unavailable'))}`",
            f"Event SHA: `{safe(env.get('GITHUB_SHA', 'unavailable'))}` "
            "(pull_request events use GitHub's synthetic merge commit).",
            f"Run: {safe(env.get('GITHUB_SERVER_URL', 'https://github.com'))}/"
            f"{safe(env.get('GITHUB_REPOSITORY', 'unavailable'))}/actions/runs/"
            f"{safe(env.get('GITHUB_RUN_ID', 'unavailable'))} · attempt {safe(env.get('GITHUB_RUN_ATTEMPT', 'unavailable'))}"]


def render(directory):
    path = directory / "results.json"
    data = json.loads(path.read_text()) if path.exists() else {"stages": {}, "verified": False}
    lines = ["## App regression evidence", *identity(), "",
             f"Evidence complete and passing: **{'yes' if data['verified'] else 'no'}**. "
             f"Job status at summary: **{safe(os.getenv('APP_JOB_STATUS', 'unknown'))}**.",
             "", "| Stage | Outcome | Seconds |", "| --- | --- | --- |"]
    for stage in data["stages"] or STAGES:
        record = data["stages"].get(stage, {"status": "unavailable"})
        status = record["status"]
        if status == "running":
            status = "interrupted / cancelled / infrastructure termination; no completed result"
        lines.append(f"| {stage} | {safe(status)} | {safe(record.get('duration_seconds', 'unavailable'))} |")
        if status in ('timed_out', 'interrupted'):
            lines.append(f"| {stage} termination | Wrapper exit {safe(record.get('exit_code', 'unavailable'))}; "
                         f"command exit {safe(record.get('command_exit_code', 'not started / unavailable'))}; "
                         f"forced kill {safe(record.get('forced_kill', False))} | — |")
        if record.get('cleanup_errors') or record.get('cleanup_reap_error'):
            lines.append(f"| {stage} cleanup | Cleanup unverified: "
                         f"{safe(record.get('cleanup_errors', []))}; "
                         f"{safe(record.get('cleanup_reap_error', ''))} | — |")
        if stage in SUITES:
            tests = record.get("tests")
            if tests:
                lines.append(f"| {stage} tests | {tests['totalTestCount']} cases: {tests['passedTests']} passed, "
                             f"{tests['failedTests']} failed, {tests['skippedTests']} skipped, "
                             f"{tests['expectedFailures']} expected failures; "
                             f"{safe(tests['executions'])} executions including dynamic parameters | — |")
            else:
                lines.append(f"| {stage} tests | {safe(record.get('results_error', 'Counts unavailable'))} | — |")
    if data.get("evidence_error"):
        lines.append("Evidence rejected: " + safe(data["evidence_error"]))
    lines += ["", "Counts come from xcresulttool across XCTest and Swift Testing. "
              "Parameterized executions and test cases are different counts; no console totals are added.", ""]
    toolchain = directory / "toolchain.txt"
    lines.append("Toolchain: " + safe(toolchain.read_text().strip() if toolchain.exists() else "unavailable (preparation did not complete)"))
    cache = data.get('cache', {})
    cache_path = directory / 'cache-status.json'
    if 'cache' not in data and cache_path.exists():
        try:
            cache = json.loads(cache_path.read_text())
        except (ValueError, OSError):
            cache = {'classification': 'unavailable', 'error': 'Unreadable cache evidence'}
    if not isinstance(cache, dict):
        cache = {'classification': 'unavailable', 'error': 'Unreadable cache evidence: expected an object'}
    lines.append("SwiftPM cache: " + safe(" / ".join(str(cache.get(k, 'unavailable')) for k in
                 ('classification', 'decision', 'status'))) + ". Skipped/failed/partial restore is neither a warm hit nor a cold miss.")
    if cache.get('error'):
        lines.append('Cache evidence error: ' + safe(cache['error']))
    lines.append(f"Requested Debug destination: {NAME} / iOS {VERSION} ({BUILD}) / arm64. "
                 "Unsigned Release destination: generic iOS Simulator (compilation/packaging only).")
    preparation = directory / 'simulator.json'
    if preparation.exists():
        try:
            device_record = json.loads(preparation.read_text())
            if not isinstance(device_record, dict):
                raise ValueError('Expected a simulator evidence object')
            lines.append("Simulator preparation: " + safe(" / ".join(str(device_record.get(k, 'unknown')) for k in
                         ('status', 'ownership', 'simulator_id'))))
        except (ValueError, OSError, TypeError) as error:
            lines.append(f'Simulator preparation: unavailable; unreadable lifecycle evidence ({type(error).__name__}).')
    cleanup_record = data['stages'].get('cleanup', {})
    lines.append("Simulator cleanup: " + safe(" / ".join(str(cleanup_record.get(k, 'unavailable')) for k in
                 ('status', 'operation', 'readback_verified', 'error'))))
    for stage in SUITES:
        for device in data["stages"].get(stage, {}).get("tests", {}).get("devices", []):
            details = device.get("device", {})
            lines.append(f"Observed {stage} destination: " + safe(" / ".join(str(details.get(k, "unknown")) for k in
                         ("deviceName", "osVersion", "osBuildNumber", "architecture", "deviceId"))))
    artifact = os.getenv("ARTIFACT_URL")
    lines += ["", f"[Logs and result bundles]({artifact}) (30-day configured retention; verify the artifact expiry in GitHub)." if artifact else
              "Artifact link unavailable; upload may have failed, been cancelled, or produced no files.",
              "Failed/incomplete stages require inspection of their logs and result bundle; missing evidence is never a pass. "
              "No live authentication, signed archive, distribution, VoiceOver, or physical-device acceptance is established."]
    return "\n".join(lines) + "\n"


def gate_summary(needs):
    mode = needs.get("classify", {}).get("outputs", {}).get("mode", "unavailable")
    lines = ["## CI run summary", *identity(), "", f"Classification: **{safe(mode)}**.", ""]
    for job in ("classify", "checks", "build-and-test", "ui-shards"):
        lines.append(f"- {job}: **{safe(needs.get(job, {}).get('result', 'unavailable'))}**")
    if mode == "docs" and all(needs.get(job, {}).get("result") == "skipped" for job in ("build-and-test", "ui-shards")):
        lines.append("\nApp tests and unsigned Release intentionally omitted for docs-only changes; "
                     "test counts, app duration, toolchain/device evidence and app artifacts: not applicable. No app pass claimed.")
    else:
        lines.append("\nComplete same-attempt evidence validation: **" + safe(os.getenv("EVIDENCE_STATUS", "unavailable")) + "**.")
        lines.append("\nSee the app job summary for toolchain, destinations, test counts, stage durations and artifacts. "
                     "Failed, cancelled, unexpectedly skipped or unavailable jobs do not establish a pass.")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("collect", "render", "gate"))
    parser.add_argument("--directory", type=Path, default=Path("build"))
    args = parser.parse_args()
    if args.command == "collect":
        sys.exit(0 if collect(args.directory, os.getenv("CI_PART")) else 1)
    else:
        summary = gate_summary(json.loads(os.environ["NEEDS_JSON"])) if args.command == "gate" else render(args.directory)
        print(summary)
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(summary)
