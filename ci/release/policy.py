"""Validate synthetic packages and model approval/recovery without external calls."""
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import re

SHA = re.compile(r"[0-9a-f]{40}\Z")
DIGEST = re.compile(r"[0-9a-f]{64}\Z")
FILES = {"app/info.json", "app/firebase.json", "app/content.json",
         "app/PrivacyInfo.xcprivacy", "app/executable"}
MARKERS = (b"CISmokeMode", b"--ci-smoke", b"Offline CI smoke", b"ci-smoke-offline",
           b"DAILY_WHISKERS_TEST_PASSWORD", b"CaptureApp", b"ProfilingHarness")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True, allow_nan=False).encode()


def fixture_record(**values):
    return dict(values, mode="fixture", release_eligible=False)


def safe_path(name):
    return (isinstance(name, str) and bool(name) and "\\" not in name
            and "\x00" not in name and not PurePosixPath(name).is_absolute()
            and all(part not in {"", ".", ".."} for part in name.split("/")))


def read_package(root):
    """Read only a small, extracted synthetic directory; never extract archives."""
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError("package_path")
    root = root.resolve()
    files = {}
    for entry in root.rglob("*"):
        if entry.is_symlink():
            raise ValueError("package_path")
        if entry.is_dir():
            continue
        if not entry.is_file() or entry.stat().st_size > 1024 * 1024:
            raise ValueError("package_path")
        name = entry.relative_to(root).as_posix()
        if not safe_path(name) or name not in FILES:
            raise ValueError("package_inventory")
        files[name] = entry.read_bytes()
    if set(files) != FILES:
        raise ValueError("package_inventory")
    return files


def validate(manifest, expected, root, inspection, ci, now):
    """All successful assertions are fixture assertions, never real signing proof."""
    errors = []

    def require(condition, code):
        if not condition and code not in errors:
            errors.append(code)

    try:
        require(set(manifest) == {"schema", "mode", "release_eligible", "identity",
                                  "inputs", "files", "object_version"}, "schema")
        require(type(manifest["schema"]) is int and manifest["schema"] == 1
                and manifest["mode"] == "fixture"
                and manifest["release_eligible"] is False, "schema")
        identity = manifest["identity"]
        require(identity == expected["identity"], "identity")
        require(all(isinstance(identity[k], str) and SHA.fullmatch(identity[k])
                    for k in ("source_sha", "tree_sha", "controller_sha", "tag_object")),
                "identity")
        require(manifest["inputs"] == expected["inputs"]
                and all(isinstance(v, str) and DIGEST.fullmatch(v)
                        for v in manifest["inputs"].values()), "input_digest")
        require(manifest["object_version"] == expected["object_version"], "object_version")
        require(set(manifest["files"]) == FILES
                and all(safe_path(k) for k in manifest["files"]), "package_inventory")
        files = read_package(root)
        require({k: digest(v) for k, v in files.items()} == manifest["files"], "package_digest")
        info = json.loads(files["app/info.json"])
        require(info["identity"] == identity, "package_identity")
        require(info["ITSAppUsesNonExemptEncryption"] is False, "encryption")
        require(info["device_families"] == [1, 2]
                and all(type(v) is int for v in info["device_families"]) and info["minimum_os"] == "26.2"
                and info["orientations"] == ["portrait", "landscape"], "package_platform")
        firebase = json.loads(files["app/firebase.json"])
        require(firebase == expected["firebase"]
                and digest(files["app/firebase.json"]) == expected["inputs"]["firebase"]
                and firebase.get("fixture_kind") == "distribution-policy-test", "firebase")
        require(not any(marker in files["app/executable"] for marker in MARKERS), "forbidden_marker")
        require(inspection["mode"] == "fixture" and inspection["signature"] == "valid", "signature")
        profile = inspection["profile"]
        require(profile["team"] == identity["team"]
                and profile["application_identifier"] == identity["team"] + "." + identity["bundle"]
                and type(profile["expires"]) is int and profile["expires"] > now
                and profile["distribution"] == "app-store"
                and profile["get_task_allow"] is False and profile["devices"] == [], "profile")
        require(inspection["entitlements"] == expected["entitlements"]
                and profile["entitlements"] == expected["entitlements"], "entitlements")
        require(inspection["app_uuids"] == inspection["dsym_uuids"] == expected["uuids"], "symbols")
        require(ci["source_sha"] == ci["tested_sha"] == identity["source_sha"]
                and ci["mode"] == "full"
                and ci["jobs"] == {k: "success" for k in ("checks", "app", "gate")}, "ci")
        require(set(ci["suites"]) == {"unit", "smoke"}, "ci")
        for suite in ci["suites"].values():
            require(set(suite) == {"passed", "failed", "skipped", "expected_failures"}
                    and all(type(v) is int and v >= 0 for v in suite.values())
                    and suite["passed"] > 0
                    and suite["failed"] == suite["skipped"] == suite["expected_failures"] == 0, "ci")
    except (KeyError, TypeError, ValueError, AttributeError, OSError, RecursionError):
        require(False, "unreadable_evidence")
    return fixture_record(passed=not errors, errors=errors)


def approval_valid(approval, manifest, attempt, now):
    """A simulated approval cannot be used as authority for any external action."""
    try:
        return (approval["mode"] == "fixture" and approval["status"] == "approved"
                and approval["action"] == "simulate-upload" and type(attempt) is int and attempt > 0
                and type(approval["attempt"]) is int and approval["attempt"] == attempt
                and type(approval["issued"]) is int and type(approval["expires"]) is int
                and approval["issued"] <= now < approval["expires"]
                and approval["manifest_digest"] == digest(canonical(manifest))
                and approval["package_digest"] == digest(canonical(manifest["files"]))
                and approval["identity"] == manifest["identity"])
    except (KeyError, TypeError, ValueError):
        return False


def manual_distribution_confirmed(settings):
    return (isinstance(settings, dict) and settings.get("known") is True
            and settings.get("automatic") is False)


def storage_current(receipt, now):
    return (isinstance(receipt, dict) and receipt.get("saved") is True
            and type(receipt.get("expires")) is int and receipt["expires"] > now)


@dataclass(frozen=True)
class Reconciliation:
    """Fixture decision plus monotonic acceptance evidence, bound to one package."""
    state: str
    acceptance_seen: bool
    package_digest: str


def reconcile(observations, package_digest, acceptance_seen=False):
    """Inspect supplied records only. Uncertainty must not discard bound acceptance.

    More than three responses cannot establish a definitive outcome, but valid
    acceptance anywhere in the supplied batch still survives. No polling occurs.
    """
    seen = acceptance_seen is True
    if (not isinstance(observations, list)
            or not isinstance(package_digest, str) or not DIGEST.fullmatch(package_digest)):
        return Reconciliation("unknown", seen, package_digest)
    uncertain = not 0 < len(observations) <= 3 or type(acceptance_seen) is not bool
    state = "unknown"
    for observation in observations:
        if (not isinstance(observation, dict)
                or set(observation) != {"complete", "outcome", "package_digest"}
                or observation["complete"] is not True
                or observation["package_digest"] != package_digest):
            uncertain = True
            continue
        outcome = observation["outcome"]
        if outcome == "rejected_before_acceptance":
            uncertain |= len(observations) != 1 or seen
            state = "rejected"
        elif isinstance(outcome, str) and outcome in {"processing", "processed", "processing_failed"}:
            seen = True
            uncertain |= state in {"processed", "processing_failed", "rejected"} and outcome != state
            state = outcome
        else:
            uncertain = True
    return Reconciliation("unknown" if uncertain else state, seen, package_digest)
