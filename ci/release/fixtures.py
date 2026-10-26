"""Generated synthetic evidence; contains no app binary or production configuration."""
from copy import deepcopy

from .policy import canonical, digest, fixture_record

NOW = 1000


def make(root):
    identity = dict(source_sha="1" * 40, tree_sha="2" * 40, controller_sha="3" * 40,
                    tag_object="4" * 40, app="fixture-app", bundle="invalid.example.fixture",
                    team="FIXTURE", version="0.0", build="fixture-1", platform="fixture-ios")
    firebase = {"fixture_kind": "distribution-policy-test", "bundle": identity["bundle"],
                "project": "synthetic-only", "private_sentinel": "DO_NOT_PUBLISH_FIXTURE_CONFIG"}
    entitlements = {"associated_domains": ["webcredentials:fixture.invalid"]}
    files = {
        "app/info.json": canonical(dict(identity=identity, ITSAppUsesNonExemptEncryption=False,
                                        device_families=[1, 2], minimum_os="26.2",
                                        orientations=["portrait", "landscape"])),
        "app/firebase.json": canonical(firebase),
        "app/content.json": b'{"fixture":true}',
        "app/PrivacyInfo.xcprivacy": b"synthetic privacy manifest; not a plist",
        "app/executable": b"synthetic bytes; not a Mach-O executable",
    }
    for name, data in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    inputs = {"lock": digest(b"fixture lock"), "export_options": digest(b"fixture export"),
              "firebase": digest(files["app/firebase.json"])}
    expected = dict(identity=deepcopy(identity), inputs=inputs.copy(), object_version="fixture-v1",
                    firebase=firebase, entitlements=entitlements, uuids={"arm64": "FIXTURE-UUID"})
    manifest = fixture_record(schema=1, identity=identity, inputs=inputs.copy(),
                              files={k: digest(v) for k, v in files.items()}, object_version="fixture-v1")
    inspection = {"mode": "fixture", "signature": "valid", "profile": {
        "team": "FIXTURE", "application_identifier": "FIXTURE.invalid.example.fixture",
        "expires": NOW + 100, "distribution": "app-store", "get_task_allow": False,
        "devices": [], "entitlements": deepcopy(entitlements)},
        "entitlements": deepcopy(entitlements), "app_uuids": {"arm64": "FIXTURE-UUID"},
        "dsym_uuids": {"arm64": "FIXTURE-UUID"}}
    ci = {"source_sha": identity["source_sha"], "tested_sha": identity["source_sha"],
          "mode": "full", "jobs": {k: "success" for k in ("checks", "app", "gate")},
          "suites": {k: dict(passed=1, failed=0, skipped=0, expected_failures=0)
                     for k in ("unit", "smoke")}}
    return manifest, expected, inspection, ci


def approve(manifest):
    return {"mode": "fixture", "status": "approved", "action": "simulate-upload", "attempt": 1,
            "issued": NOW - 1, "expires": NOW + 10, "identity": deepcopy(manifest["identity"]),
            "manifest_digest": digest(canonical(manifest)),
            "package_digest": digest(canonical(manifest["files"]))}
