"""Behavior and negative-path tests for the offline fixture-only release model."""
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import itertools
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from release.fixtures import NOW, approve, make
from release.ledger import Ledger
from release.policy import (Reconciliation, approval_valid, canonical, digest, manual_distribution_confirmed,
                            reconcile, safe_path, storage_current, validate)
from release.rehearse import NoExternalCalls, SCENARIOS, run


class ReleasePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "package"
        self.manifest, self.expected, self.inspection, self.ci = make(self.root)

    def validate(self):
        return validate(self.manifest, self.expected, self.root, self.inspection, self.ci, NOW)

    def replace_file(self, name, value):
        data = canonical(value)
        (self.root / name).write_bytes(data)
        self.manifest["files"][name] = digest(data)

    def test_valid_is_never_release_eligible_and_digest_is_canonical(self):
        result = self.validate()
        self.assertTrue(result["passed"])
        self.assertEqual(result["mode"], "fixture")
        self.assertIs(result["release_eligible"], False)
        self.assertEqual(digest(canonical(self.manifest)), digest(canonical(dict(reversed(list(self.manifest.items()))))))
        self.assertNotIn("DO_NOT_PUBLISH_FIXTURE_CONFIG", json.dumps(result))

    def test_schema_missing_invalid_and_identity_fields_fail_closed(self):
        original = deepcopy(self.manifest)
        for field in original:
            with self.subTest(missing=field):
                self.manifest = deepcopy(original)
                del self.manifest[field]
                self.assertFalse(self.validate()["passed"])
        for field, value in (("schema", True), ("schema", "1"), ("schema", 2),
                             ("mode", "production"), ("release_eligible", True),
                             ("object_version", "other"), ("files", {}), ("extra", "unknown")):
            with self.subTest(field=field, value=value):
                self.manifest = deepcopy(original)
                self.manifest[field] = value
                self.assertFalse(self.validate()["passed"])
        for field in original["identity"]:
            with self.subTest(identity=field):
                self.manifest = deepcopy(original)
                self.manifest["identity"][field] = "wrong"
                self.assertFalse(self.validate()["passed"])

    def test_package_content_and_digest_rejections(self):
        for name in self.manifest["files"]:
            with self.subTest(name=name):
                path = self.root / name
                data = path.read_bytes()
                path.write_bytes(data + b"x")
                self.assertFalse(self.validate()["passed"])
                path.unlink()
                self.assertFalse(self.validate()["passed"])
                path.write_bytes(data)
        extra = self.root / "app/extra-executable"
        extra.write_bytes(b"extra")
        self.assertFalse(self.validate()["passed"])

    def test_encryption_requires_boolean_false_and_platform_is_checked(self):
        info = json.loads((self.root / "app/info.json").read_bytes())
        for value in (None, "false", True, 0):
            with self.subTest(value=value):
                self.replace_file("app/info.json", dict(info, ITSAppUsesNonExemptEncryption=value))
                self.assertIn("encryption", self.validate()["errors"])
        missing = dict(info)
        del missing["ITSAppUsesNonExemptEncryption"]
        self.replace_file("app/info.json", missing)
        self.assertFalse(self.validate()["passed"])
        for field, value in (("device_families", [1]), ("device_families", [True, 2]),
                             ("minimum_os", "17.0"), ("minimum_os", "26.0"),
                             ("minimum_os", "26.1"), ("minimum_os", "99"), ("orientations", [])):
            self.replace_file("app/info.json", dict(info, **{field: value}))
            self.assertIn("package_platform", self.validate()["errors"])

    def test_firebase_must_match_expected_digest_and_registration(self):
        for value in ({"fixture_kind": "ci-test-config"}, {"fixture_kind": "different-but-unapproved"}):
            self.replace_file("app/firebase.json", value)
            self.assertIn("firebase", self.validate()["errors"])
        self.manifest["inputs"]["lock"] = "0" * 64
        self.assertIn("input_digest", self.validate()["errors"])

    def test_marker_and_symlink_never_escape_package(self):
        for marker in (b"CISmokeMode", b"--ci-smoke", b"Offline CI smoke", b"ci-smoke-offline",
                       b"DAILY_WHISKERS_TEST_PASSWORD", b"CaptureApp", b"ProfilingHarness"):
            path = self.root / "app/executable"
            path.write_bytes(marker)
            self.manifest["files"]["app/executable"] = digest(marker)
            self.assertIn("forbidden_marker", self.validate()["errors"])
        outside = Path(self.temporary.name) / "outside"
        outside.write_text("private sentinel")
        path.unlink()
        path.symlink_to(outside)
        self.assertFalse(self.validate()["passed"])
        self.assertEqual(outside.read_text(), "private sentinel")
        for value in ("../outside", "/tmp/outside", "a/../outside", "a//b", "a/./b", "a\\b", ""):
            self.assertFalse(safe_path(value))

    def test_signature_profile_entitlements_symbols_failures(self):
        original = deepcopy(self.inspection)
        for field, value in (("signature", "unavailable"), ("signature", "failed"),
                             ("mode", "live"), ("entitlements", {}), ("app_uuids", {}),
                             ("dsym_uuids", {"arm64": "different"})):
            self.inspection = deepcopy(original)
            self.inspection[field] = value
            self.assertFalse(self.validate()["passed"])
        for field, value in (("expires", NOW), ("expires", True), ("team", "OTHER"),
                             ("application_identifier", "wrong"), ("distribution", "development"),
                             ("get_task_allow", True), ("get_task_allow", 0),
                             ("devices", ["device"]), ("entitlements", {})):
            self.inspection = deepcopy(original)
            self.inspection["profile"][field] = value
            self.assertFalse(self.validate()["passed"])

    def test_ci_counts_and_exact_identity_are_required(self):
        original = deepcopy(self.ci)
        for field, value in (("source_sha", "f" * 40), ("tested_sha", "e" * 40),
                             ("mode", "docs"), ("jobs", {}), ("suites", {})):
            self.ci = deepcopy(original)
            self.ci[field] = value
            self.assertFalse(self.validate()["passed"])
        for suite in ("unit", "smoke"):
            for field, value in (("passed", 0), ("failed", 1), ("skipped", 1),
                                 ("expected_failures", 1), ("expected_failures", None),
                                 ("expected_failures", False)):
                self.ci = deepcopy(original)
                self.ci["suites"][suite][field] = value
                self.assertFalse(self.validate()["passed"])
        for status in ("skipped", "cancelled", "failure", "timed_out"):
            self.ci = deepcopy(original)
            self.ci["jobs"]["app"] = status
            self.assertFalse(self.validate()["passed"])

    def test_approval_binds_digests_action_attempt_identity_and_time(self):
        approval = approve(self.manifest)
        self.assertTrue(approval_valid(approval, self.manifest, 1, NOW))
        for field in approval:
            invalid = deepcopy(approval)
            del invalid[field]
            self.assertFalse(approval_valid(invalid, self.manifest, 1, NOW), field)
        for field, value in (("status", "denied"), ("action", "upload"), ("mode", "live"),
                             ("attempt", 0), ("attempt", True), ("issued", NOW + 1),
                             ("expires", NOW), ("manifest_digest", "0" * 64),
                             ("package_digest", "0" * 64), ("identity", {})):
            self.assertFalse(approval_valid(dict(approval, **{field: value}), self.manifest, 1, NOW))
        self.manifest["files"]["app/executable"] = "f" * 64
        self.assertFalse(approval_valid(approval, self.manifest, 1, NOW))

    def test_reconciliation_never_infers_no_upload_from_absence_or_error(self):
        package = "d" * 64
        for outcome in ("absent", "duplicate", "401", "403", "429", "503", "unexpected"):
            result = reconcile([dict(complete=True, outcome=outcome, package_digest=package)], package)
            self.assertEqual(result, Reconciliation("unknown", False, package))
        self.assertEqual(reconcile([], package), Reconciliation("unknown", False, package))
        for complete, observed in ((False, package), (True, "e" * 64)):
            result = reconcile([dict(complete=complete, outcome="processed", package_digest=observed)], package)
            self.assertEqual(result, Reconciliation("unknown", False, package))
        for outcome in ("processing", "processed", "processing_failed"):
            response = dict(complete=True, outcome=outcome, package_digest=package)
            self.assertEqual(reconcile([response], package), Reconciliation(outcome, True, package))
            # An oversized batch has an unknown outcome but cannot erase acceptance.
            self.assertEqual(reconcile([response] * 4, package), Reconciliation("unknown", True, package))
        contradictory = [dict(complete=True, outcome=x, package_digest=package) for x in ("processed", "processing")]
        self.assertEqual(reconcile(contradictory, package), Reconciliation("unknown", True, package))

    def test_definitive_rejection_requires_current_package_correlation(self):
        package = "d" * 64
        for fields in ({}, {"package_digest": "e" * 64}, {"package_digest": None}):
            with self.subTest(fields=fields):
                observation = dict(complete=True, outcome="rejected_before_acceptance", **fields)
                self.assertEqual(reconcile([observation], package), Reconciliation("unknown", False, package))
        observation = dict(complete=True, outcome="rejected_before_acceptance", package_digest=package)
        self.assertEqual(reconcile([observation], package, False), Reconciliation("rejected", False, package))
        self.assertEqual(reconcile([observation], package, True), Reconciliation("unknown", True, package))
        self.assertEqual(reconcile([observation], package, None), Reconciliation("unknown", False, package))
        for invalid_digest in (None, "", "not-a-digest"):
            result = reconcile([dict(observation, package_digest=invalid_digest)], invalid_digest)
            self.assertEqual(result.state, "unknown")
            self.assertFalse(result.acceptance_seen)

    def test_only_complete_well_formed_bound_observations_establish_acceptance(self):
        package = "d" * 64
        accepted = dict(complete=True, outcome="processing", package_digest=package)
        invalid = [None, {}, dict(accepted, complete=False), dict(accepted, complete=1),
                   dict(accepted, package_digest="e" * 64), dict(accepted, package_digest=None),
                   dict(accepted, outcome="503"), dict(accepted, outcome=["processing"]),
                   dict(accepted, error="503"), {k: v for k, v in accepted.items() if k != "package_digest"}]
        for observation in invalid:
            with self.subTest(observation=observation):
                self.assertEqual(reconcile([observation], package), Reconciliation("unknown", False, package))
                for batch in ([accepted, observation], [observation, accepted]):
                    self.assertEqual(reconcile(batch, package), Reconciliation("unknown", True, package))
        self.assertEqual(reconcile(invalid, package), Reconciliation("unknown", False, package))
        for batch in ([accepted, *invalid], [*invalid, accepted]):
            self.assertEqual(reconcile(batch, package), Reconciliation("unknown", True, package))
        self.assertEqual(reconcile([accepted], package, acceptance_seen=None),
                         Reconciliation("unknown", True, package))

    def test_storage_and_distribution_require_explicit_fresh_evidence(self):
        self.assertTrue(storage_current(dict(saved=True, expires=NOW + 1), NOW))
        for receipt in ({}, None, dict(saved=False, expires=NOW + 1),
                        dict(saved=True, expires=NOW), dict(saved=True, expires=True),
                        dict(saved="true", expires=NOW + 1)):
            self.assertFalse(storage_current(receipt, NOW))
        self.assertTrue(manual_distribution_confirmed(dict(known=True, automatic=False)))
        for settings in ({}, None, dict(known=False, automatic=False), dict(known=True, automatic=True),
                         dict(known=True, automatic=0), dict(known="true", automatic=False)):
            self.assertFalse(manual_distribution_confirmed(settings))


class ReleaseLedgerTests(unittest.TestCase):
    PACKAGE = "d" * 64

    def start_intent(self, ledger, build="fixture-1"):
        self.assertTrue(ledger.reserve("fixture-app", build, "run"))
        for before, after in (("reserved", "prepared"), ("prepared", "approved"), ("approved", "upload_intent")):
            self.assertTrue(ledger.advance(build, "run", before, after, self.PACKAGE))

    def observe(self, outcome, **changes):
        return dict(dict(complete=True, outcome=outcome, package_digest=self.PACKAGE), **changes)

    def record(self, ledger, observations, build="fixture-1"):
        decision = reconcile(observations, self.PACKAGE, ledger.acceptance_seen(build))
        self.assertTrue(ledger.record_reconciliation(build, "run", ledger.state(build), decision))
        return decision

    def test_batch_acceptance_survives_incomplete_or_error_in_either_order_and_restart(self):
        faults = [self.observe("processing", complete=False), self.observe("503"),
                  self.observe("processing", package_digest="e" * 64), None,
                  self.observe("rejected_before_acceptance")]
        for outcome in ("processing", "processed", "processing_failed"):
            accepted = self.observe(outcome)
            for fault in faults:
                for batch in ([accepted, fault], [fault, accepted]):
                    with self.subTest(batch=batch), tempfile.TemporaryDirectory() as temporary:
                        path = Path(temporary) / "ledger.sqlite"
                        ledger = Ledger(path)
                        self.start_intent(ledger)
                        self.assertEqual(self.record(ledger, batch), Reconciliation("unknown", True, self.PACKAGE))
                        ledger.close()
                        ledger = Ledger(path)
                        try:
                            self.assertEqual(ledger.state("fixture-1"), "unknown")
                            self.assertTrue(ledger.acceptance_seen("fixture-1"))
                            rejection = self.record(ledger, [self.observe("rejected_before_acceptance")])
                            self.assertEqual(rejection, Reconciliation("unknown", True, self.PACKAGE))
                            self.assertEqual(ledger.state("fixture-1"), "unknown")
                        finally:
                            ledger.close()

    def test_invalid_or_unbound_batch_does_not_persist_acceptance(self):
        invalid = [self.observe("processing", complete=False), self.observe("processing", package_digest="e" * 64),
                   self.observe("processing", error="503"), None]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "ledger.sqlite"
            ledger = Ledger(path)
            self.start_intent(ledger)
            self.assertEqual(self.record(ledger, invalid), Reconciliation("unknown", False, self.PACKAGE))
            ledger.close()
            ledger = Ledger(path)
            try:
                self.assertFalse(ledger.acceptance_seen("fixture-1"))
                self.assertEqual(self.record(ledger, [self.observe("rejected_before_acceptance")]).state, "rejected")
            finally:
                ledger.close()

    def test_processing_error_and_pagination_permutations_preserve_acceptance(self):
        observations = [self.observe("processing"), self.observe("503"), self.observe("processing", complete=False)]
        for batch in itertools.permutations(observations):
            with self.subTest(batch=batch), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "ledger.sqlite"
                ledger = Ledger(path)
                self.start_intent(ledger)
                self.assertEqual(self.record(ledger, list(batch)), Reconciliation("unknown", True, self.PACKAGE))
                ledger.close()
                ledger = Ledger(path)
                try:
                    self.assertTrue(ledger.acceptance_seen("fixture-1"))
                    self.assertEqual(self.record(ledger, [self.observe("rejected_before_acceptance")]),
                                     Reconciliation("unknown", True, self.PACKAGE))
                finally:
                    ledger.close()

    def test_processing_acceptance_cannot_be_replaced_by_rejection_after_restart(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "ledger.sqlite"
            ledger = Ledger(path)
            self.start_intent(ledger)
            self.record(ledger, [self.observe("processing")])
            ledger.close()
            ledger = Ledger(path)
            try:
                self.assertTrue(ledger.acceptance_seen("fixture-1"))
                self.assertFalse(ledger.advance("fixture-1", "run", "processing", "rejected", self.PACKAGE))
                self.assertEqual(ledger.state("fixture-1"), "processing")
                self.record(ledger, [])
            finally:
                ledger.close()
            ledger = Ledger(path)
            try:
                # A stale caller may have computed rejection before acceptance was saved.
                # The atomic write must preserve current DB history, not trust that flag.
                stale = Reconciliation("rejected", False, self.PACKAGE)
                self.assertTrue(ledger.record_reconciliation("fixture-1", "run", "unknown", stale))
                self.assertEqual(ledger.state("fixture-1"), "unknown")
                self.assertTrue(ledger.acceptance_seen("fixture-1"))
            finally:
                ledger.close()

    def test_correlated_rejection_remains_possible_before_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Ledger(Path(temporary) / "ledger.sqlite")
            try:
                self.assertIsNone(ledger.acceptance_seen("fixture-missing"))
                for destination in ("upload_intent", "unknown"):
                    build = "fixture-" + destination
                    self.start_intent(ledger, build)
                    if destination == "unknown":
                        self.record(ledger, [], build)
                    self.assertFalse(ledger.acceptance_seen(build))
                    self.assertEqual(self.record(ledger, [self.observe("rejected_before_acceptance")], build).state, "rejected")
                    self.assertEqual(ledger.state(build), "rejected")
                    self.assertFalse(ledger.acceptance_seen(build))
            finally:
                ledger.close()

    def test_competing_workers_and_manual_reservation_have_one_winner(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "ledger.sqlite"
            Ledger(path).close()
            def claim(owner):
                ledger = Ledger(path)
                try:
                    return ledger.reserve("fixture-app", "fixture-1", owner)
                finally:
                    ledger.close()
            with ThreadPoolExecutor(max_workers=2) as pool:
                self.assertEqual(sorted(pool.map(claim, ["manual", "automation"])), [False, True])

    def test_intent_survives_restart_and_cannot_be_reset_or_reassigned(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "ledger.sqlite"
            ledger = Ledger(path)
            with self.assertRaises(ValueError):
                ledger.reserve("real-app", "3", "operator")
            self.start_intent(ledger)
            ledger.close()
            ledger = Ledger(path)
            try:
                self.assertEqual(ledger.state("fixture-1"), "upload_intent")
                self.assertFalse(ledger.reserve("fixture-app", "fixture-1", "retry"))
                self.assertFalse(ledger.advance("fixture-1", "run", "upload_intent", "prepared", self.PACKAGE))
                decision = reconcile([], self.PACKAGE)
                self.assertFalse(ledger.record_reconciliation("fixture-1", "other", "upload_intent", decision))
                self.assertFalse(ledger.record_reconciliation("fixture-1", "run", "approved", decision))
                self.assertFalse(ledger.record_reconciliation("fixture-1", "run", "upload_intent",
                                                              Reconciliation("unknown", True, "e" * 64)))
                self.assertEqual(ledger.state("fixture-1"), "upload_intent")
                self.assertFalse(ledger.acceptance_seen("fixture-1"))
                self.record(ledger, [])
                self.assertFalse(ledger.advance("fixture-1", "run", "unknown", "upload_intent", self.PACKAGE))
            finally:
                ledger.close()

    def test_state_cannot_substitute_for_structured_acceptance_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Ledger(Path(temporary) / "ledger.sqlite")
            self.start_intent(ledger)
            try:
                for decision in ("processing", Reconciliation("processing", False, self.PACKAGE),
                                 Reconciliation("rejected", True, self.PACKAGE),
                                 Reconciliation("unknown", 1, self.PACKAGE)):
                    self.assertFalse(ledger.record_reconciliation("fixture-1", "run", "upload_intent", decision))
                self.assertEqual(ledger.state("fixture-1"), "upload_intent")
                self.assertFalse(ledger.acceptance_seen("fixture-1"))
                self.assertFalse(ledger.advance("fixture-1", "run", "upload_intent", "processing", self.PACKAGE))
            finally:
                ledger.close()


class ReleaseRehearsalTests(unittest.TestCase):
    def test_every_scenario_matches_and_makes_zero_external_calls(self):
        report = run(list(SCENARIOS), "a" * 40, "b" * 40)
        self.assertTrue(report["passed"], report)
        self.assertEqual(len(report["results"]), len(SCENARIOS))
        self.assertEqual(report["prohibited_calls_attempted"], 0)
        self.assertEqual(report["mode"], "fixture")
        self.assertIs(report["release_eligible"], False)
        self.assertNotIn("DO_NOT_PUBLISH_FIXTURE_CONFIG", json.dumps(report))
        rows = {r["scenario"]: r for r in report["results"]}
        for name in ("processing-incomplete-restart", "incomplete-processing-restart",
                     "processing-error-restart", "error-processing-restart"):
            self.assertIs(rows[name]["reconciliation"]["acceptance_seen"], True)
            self.assertEqual(rows[name]["reconciliation"]["state"], "unknown")
        for name in ("invalid-processing-only", "unbound-processing-only"):
            self.assertIs(rows[name]["reconciliation"]["acceptance_seen"], False)

    def test_wrong_outcome_and_attempted_external_call_fail_even_if_caught(self):
        with patch("release.rehearse.scenario", return_value=("wrong", [])):
            self.assertFalse(run(["happy"], "a" * 40, "b" * 40)["passed"])
        def attempted(*args):
            try:
                subprocess.run(["must-never-execute"], check=True)
            except RuntimeError:
                pass
            return "processed", []
        with patch("release.rehearse.scenario", side_effect=attempted):
            report = run(["happy"], "a" * 40, "b" * 40)
            self.assertFalse(report["passed"])
            self.assertEqual(report["prohibited_calls_attempted"], 1)

    def test_audit_guard_blocks_socket_before_network_use(self):
        with NoExternalCalls() as guard:
            with self.assertRaises(RuntimeError):
                socket.socket()
        self.assertEqual(guard.attempts, 1)

    def test_invalid_cli_identity_and_scenario_are_rejected(self):
        for source in ("codex/develop", "a" * 39, "A" * 40, "$(command)", "a" * 40 + "\n"):
            with self.assertRaises(ValueError):
                run(["happy"], source, "b" * 40)
        with self.assertRaises(ValueError):
            run(["not-a-scenario"], "a" * 40, "b" * 40)


if __name__ == "__main__":
    unittest.main()
