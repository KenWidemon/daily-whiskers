"""Fail-safe change classification and the required CI gate's result policy."""
import argparse
import json
import os
from pathlib import PurePosixPath
import subprocess

DOC_FILES = {"AGENTS.md", "DailyWhiskers/README.md", "ci/screenshots/README.md", ".github/pull_request_template.md"}


def docs_only(paths):
    return bool(paths) and all(
        path in DOC_FILES or (
            path.startswith("docs/") and path.endswith(".md")
            and ".." not in PurePosixPath(path).parts
        ) for path in paths
    )


def classify(base, head):
    try:
        ancestor = subprocess.check_output(
            ["git", "merge-base", base, head], text=True).strip()
        # Disabling rename detection exposes both sides, including moves out of docs.
        output = subprocess.check_output(
            ["git", "diff", "--name-only", "--no-renames", "-z", ancestor, head, "--"])
        paths = output.decode("utf-8").rstrip("\0").split("\0") if output else []
        return "docs" if docs_only(paths) else "full"
    except (subprocess.CalledProcessError, UnicodeError, OSError):
        return "full"


def gate(needs):
    if set(needs) != {"classify", "checks", "build-and-test"}:
        return False
    classification = needs["classify"]
    mode = classification.get("outputs", {}).get("mode")
    return (
        classification.get("result") == "success"
        and mode in {"docs", "full"}
        and needs["checks"].get("result") == "success"
        and needs["build-and-test"].get("result") == (
            "skipped" if mode == "docs" else "success")
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["classify", "gate"])
    args = parser.parse_args()
    if args.command == "classify":
        mode = classify(os.environ["BASE_SHA"], os.environ["HEAD_SHA"]) if os.environ.get("EVENT_NAME") == "pull_request" else "full"
        print(f"Validation mode: {mode}")
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write(f"mode={mode}\n")
    else:
        results = json.loads(os.environ["NEEDS_JSON"])
        print(json.dumps(results, indent=2))
        if not gate(results):
            raise SystemExit("CI Gate failed: required results were not satisfied")
