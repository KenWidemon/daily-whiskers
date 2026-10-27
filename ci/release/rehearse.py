"""Fixture-only CLI: JSON to stdout, temporary files only, no production adapters."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

from .fixtures import NOW, approve, make
from .ledger import Ledger
from .policy import (SHA, approval_valid, canonical, digest, fixture_record,
                     manual_distribution_confirmed, reconcile, storage_current, validate)

# Expected outcomes are separate from execution. Unexpected outcomes fail the CLI.
SCENARIOS = {
    "happy": "processed", "wrong-source": "blocked", "wrong-controller": "blocked",
    "wrong-tag": "blocked", "schema": "blocked", "encryption": "blocked",
    "firebase": "blocked", "missing-resource": "blocked", "tampered": "blocked",
    "unsafe-path": "blocked", "signature": "blocked", "profile": "blocked",
    "symbols": "blocked", "expected-failure": "blocked", "missing-ci": "blocked",
    "missing-approval": "approval-blocked", "denied": "approval-blocked",
    "stale": "approval-blocked", "changed-approval": "approval-blocked",
    "wrong-action": "approval-blocked", "previous-attempt": "approval-blocked",
    "auto-distribution": "distribution-blocked", "unknown-distribution": "distribution-blocked",
    "duplicate": "reservation-blocked", "manual-reservation": "reservation-blocked",
    "lost-receipt": "unknown", "duplicate-response": "unknown", "partial-page": "unknown",
    "delayed-visibility": "unknown", "unauthorized": "unknown", "rate-limited": "unknown",
    "server-error": "unknown", "conflicting-build": "unknown", "processing": "processing",
    "processing-failed": "processing_failed", "definitive-rejection": "rejected",
    "missing-object": "restore-blocked", "overwritten-object": "restore-blocked",
    "expired-object": "restore-blocked", "receipt-save-failed": "restore-blocked",
    "uncorrelated-rejection": "unknown", "missing-rejection-digest": "unknown",
    "rejection-after-processing-restart": "unknown",
    "processing-incomplete-restart": "unknown", "incomplete-processing-restart": "unknown",
    "processing-error-restart": "unknown", "error-processing-restart": "unknown",
    "invalid-processing-only": "unknown", "unbound-processing-only": "unknown",
}


class NoExternalCalls:
    """CPython audit guard, defense in depth for this fixed fixture runner only.

    Not a sandbox for arbitrary code. Disabled hooks remain registered but inert.
    A blocked attempt counts as failure even if another function catches it.
    """
    def __init__(self):
        self.active = False
        self.attempts = 0

    def audit(self, event, args):
        if self.active and (event.startswith(("socket.", "subprocess.", "ctypes."))
                            or event in {"os.system", "os.exec", "os.posix_spawn", "os.fork", "os.forkpty"}):
            self.attempts += 1
            raise RuntimeError("external_call_blocked")

    def __enter__(self):
        sys.addaudithook(self.audit)
        self.active = True
        return self

    def __exit__(self, *args):
        self.active = False


def scenario(name, directory):
    package = directory / "package"
    manifest, expected, inspection, ci = make(package)
    if name in {"wrong-source", "wrong-controller", "wrong-tag"}:
        key = {"wrong-source": "source_sha", "wrong-controller": "controller_sha", "wrong-tag": "tag_object"}[name]
        manifest["identity"][key] = "f" * 40
    elif name == "schema":
        manifest["schema"] = 99
    elif name in {"encryption", "firebase"}:
        key = "app/info.json" if name == "encryption" else "app/firebase.json"
        data = json.loads((package / key).read_bytes())
        if name == "encryption":
            data["ITSAppUsesNonExemptEncryption"] = "false"
        else:
            data["fixture_kind"] = "ci-test-config"
        (package / key).write_bytes(canonical(data))
        manifest["files"][key] = digest(canonical(data))
    elif name == "missing-resource":
        (package / "app/content.json").unlink()
    elif name == "tampered":
        (package / "app/executable").write_bytes(b"changed")
    elif name == "unsafe-path":
        manifest["files"]["../outside"] = "0" * 64
    elif name == "signature":
        inspection["signature"] = "unavailable"
    elif name == "profile":
        inspection["profile"]["expires"] = NOW
    elif name == "symbols":
        inspection["dsym_uuids"] = {}
    elif name == "expected-failure":
        ci["suites"]["unit"]["expected_failures"] = 1
    elif name == "missing-ci":
        ci = {}

    result = validate(manifest, expected, package, inspection, ci, NOW)
    if not result["passed"]:
        return "blocked", result["errors"]

    # Preserve and independently read back synthetic bytes before simulated approval.
    sealed = canonical(manifest)
    store = directory / "stored"
    shutil.copytree(package, store)
    manifest_file = directory / "manifest.json"
    manifest_file.write_bytes(sealed)
    if name == "missing-object":
        (store / "app/content.json").unlink()
    elif name == "overwritten-object":
        (store / "app/executable").write_bytes(b"truncated")
    elif name == "receipt-save-failed":
        manifest_file.unlink()
    receipt = dict(saved=manifest_file.is_file(), expires=NOW if name == "expired-object" else NOW + 100)
    if not storage_current(receipt, NOW):
        return "restore-blocked", ["storage_unavailable"]
    restored = json.loads(manifest_file.read_bytes())
    if digest(manifest_file.read_bytes()) != digest(sealed) or not validate(
            restored, expected, store, inspection, ci, NOW)["passed"]:
        return "restore-blocked", ["restore_verification"]

    approval = approve(manifest)
    if name == "missing-approval":
        approval = {}
    elif name in {"denied", "stale", "changed-approval", "wrong-action", "previous-attempt"}:
        key, value = {"denied": ("status", "denied"), "stale": ("expires", NOW),
                      "changed-approval": ("manifest_digest", "0" * 64),
                      "wrong-action": ("action", "release"), "previous-attempt": ("attempt", 0)}[name]
        approval[key] = value
    if not approval_valid(approval, manifest, 1, NOW):
        return "approval-blocked", ["approval"]
    distribution = dict(known=name != "unknown-distribution", automatic=name == "auto-distribution")
    if not manual_distribution_confirmed(distribution):
        return "distribution-blocked", ["distribution_not_confirmed_manual"]

    ledger_path = directory / "ledger.sqlite"
    ledger = Ledger(ledger_path)
    try:
        if name in {"duplicate", "manual-reservation"}:
            ledger.reserve("fixture-app", "fixture-1", "manual" if name == "manual-reservation" else "other-run")
        if not ledger.reserve("fixture-app", "fixture-1", "rehearsal"):
            return "reservation-blocked", ["reservation_conflict"]
        package_digest = digest(canonical(manifest["files"]))
        for before, after in (("reserved", "prepared"), ("prepared", "approved"), ("approved", "upload_intent")):
            if not ledger.advance("fixture-1", "rehearsal", before, after, package_digest):
                raise RuntimeError("ledger_transition")
        # No send function exists. All observations below are supplied fixture data.
        observation = dict(complete=True, outcome="processed", package_digest=package_digest)
        outcomes = {"duplicate-response": "duplicate", "delayed-visibility": "absent",
                    "unauthorized": "401", "rate-limited": "429", "server-error": "503",
                    "processing": "processing", "processing-failed": "processing_failed",
                    "definitive-rejection": "rejected_before_acceptance",
                    "uncorrelated-rejection": "rejected_before_acceptance",
                    "missing-rejection-digest": "rejected_before_acceptance",
                    "rejection-after-processing-restart": "rejected_before_acceptance"}
        if name in outcomes:
            observation["outcome"] = outcomes[name]
        if name == "partial-page":
            observation["complete"] = False
        if name in {"conflicting-build", "uncorrelated-rejection"}:
            observation["package_digest"] = "0" * 64
        if name == "missing-rejection-digest":
            del observation["package_digest"]
        if name == "rejection-after-processing-restart":
            accepted = dict(complete=True, outcome="processing", package_digest=package_digest)
            if not ledger.record_reconciliation("fixture-1", "rehearsal", "upload_intent",
                                                 reconcile([accepted], package_digest)):
                raise RuntimeError("ledger_transition")
            ledger.close()
            ledger = Ledger(ledger_path)
        if name == "lost-receipt":
            ledger.close()
            ledger = Ledger(ledger_path)
            observations = []
        else:
            observations = [observation]
        batch_restart = name in {"processing-incomplete-restart", "incomplete-processing-restart",
                                "processing-error-restart", "error-processing-restart"}
        accepted = dict(complete=True, outcome="processing", package_digest=package_digest)
        if batch_restart:
            fault = dict(accepted, complete=False) if "incomplete" in name else dict(accepted, outcome="503")
            observations = [accepted, fault] if name.startswith("processing-") else [fault, accepted]
        elif name == "invalid-processing-only":
            observations = [dict(accepted, complete=False)]
        elif name == "unbound-processing-only":
            observations = [dict(accepted, package_digest="0" * 64)]
        decision = reconcile(observations, package_digest, ledger.acceptance_seen("fixture-1"))
        if not ledger.record_reconciliation("fixture-1", "rehearsal", ledger.state("fixture-1"), decision):
            raise RuntimeError("ledger_transition")
        if batch_restart:
            ledger.close()
            ledger = Ledger(ledger_path)
            if not ledger.acceptance_seen("fixture-1"):
                raise RuntimeError("acceptance_evidence_lost")
            rejection = dict(accepted, outcome="rejected_before_acceptance")
            decision = reconcile([rejection], package_digest, ledger.acceptance_seen("fixture-1"))
            if not ledger.record_reconciliation("fixture-1", "rehearsal", "unknown", decision):
                raise RuntimeError("ledger_transition")
        if name in {"invalid-processing-only", "unbound-processing-only"} and ledger.acceptance_seen("fixture-1"):
            raise RuntimeError("invalid_acceptance_evidence")
        (directory / "reconciliation.json").write_bytes(canonical(dict(
            state=ledger.state("fixture-1"), acceptance_seen=ledger.acceptance_seen("fixture-1"),
            package_digest=package_digest)))
        return ledger.state("fixture-1"), []
    finally:
        ledger.close()


def run(names, controller_sha, candidate_sha):
    if not SHA.fullmatch(controller_sha) or not SHA.fullmatch(candidate_sha):
        raise ValueError("full_sha_required")
    if not names or any(name not in SCENARIOS for name in names):
        raise ValueError("unknown_scenario")
    results = []
    with NoExternalCalls() as guard:
        for name in names:
            with tempfile.TemporaryDirectory(prefix="dw-release-fixture-") as temporary:
                provenance = {}
                reconciliation = {}
                try:
                    observed, errors = scenario(name, Path(temporary))
                    saved = Path(temporary) / "manifest.json"
                    if saved.is_file():
                        data = saved.read_bytes()
                        provenance = {"prepared_manifest_sha256": digest(data),
                                      "package_inventory_sha256": digest(canonical(json.loads(data)["files"]))}
                    saved_decision = Path(temporary) / "reconciliation.json"
                    if saved_decision.is_file():
                        data = json.loads(saved_decision.read_bytes())
                        reconciliation = {k: data[k] for k in ("state", "acceptance_seen", "package_digest")}
                except Exception:
                    # Do not expose arbitrary input, exception messages or private paths.
                    observed, errors = "harness-error", ["fixture_execution_failed"]
            results.append(dict(scenario=name, expected=SCENARIOS[name], observed=observed,
                                matched=observed == SCENARIOS[name], errors=errors, provenance=provenance,
                                reconciliation=reconciliation))
    implementation = {p.name: digest(p.read_bytes()) for p in sorted(Path(__file__).parent.glob("*.py"))}
    return fixture_record(schema=1, execution=dict(declared_controller_sha=controller_sha,
                          declared_candidate_sha=candidate_sha,
                          git_verification="CLI checks format only; workflow performs Git preflight"),
                          implementation_sha256=implementation,
                          scenario_set_sha256=digest(canonical({"fixture_set": 1, "scenarios": names})),
                          results=results, prohibited_calls_attempted=guard.attempts,
                          passed=all(r["matched"] for r in results) and guard.attempts == 0,
                          unverified=["signing", "Apple validation and processing", "physical acceptance",
                                      "environment enforcement", "production storage and credentials"])


class Parser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, "Invalid rehearsal arguments; use --help.\n")


def main():
    parser = Parser(description=__doc__)
    parser.add_argument("--controller-sha", required=True)
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--scenario", choices=["all", *SCENARIOS], default="all")
    args = parser.parse_args()
    try:
        report = run(list(SCENARIOS) if args.scenario == "all" else [args.scenario],
                     args.controller_sha, args.candidate_sha)
    except ValueError:
        print(json.dumps(fixture_record(passed=False, errors=["invalid_input"])))
        return 2
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
