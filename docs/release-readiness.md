# Release Configuration and Security

## Current Status (September 13, 2026)

Current remaining work lives in the [release checklist](release-checklist.md).
This document retains configuration guidance and historical signing evidence.
September 9 archive/export/validation passed for that source only; those artifacts
predate the merged VoiceOver and guest-first changes and are **not the current RC**.
A newly frozen RC needs fresh archive/export/validation and candidate acceptance.
No build upload or review submission is recorded. Privacy/support and App Store
copy are reconciled, and dedicated reviewer preparation is complete with
owner-verified credentials. The pre-upload account/metadata audit is complete;
final-candidate checks remain required. See [distribution evidence](distribution-readiness.md#account-and-metadata-audit-september-13-2026)
and the [documentation map](README.md).

## Configuration

- `project.yml` is the source of truth; regenerate with `xcodegen generate`.
- Bundle ID remains `com.example.kenwidemon.dailywhiskers`. The local Firebase
  plist's `BUNDLE_ID` matches. The `example` component is not a reason to rename
  an existing Firebase registration. The existing App Store Connect record is
  `6809050612`; do not create a duplicate or rename its confirmed bundle ID.
- Initial marketing version is `1.0`, build `1`. These are starting values,
  not a claim that the build number is unused in App Store Connect.
- iOS deployment target remains 17.0; iPhone and iPad remain supported.
- All 18 AppIcon slots were checked against their declared pixel dimensions;
  every referenced PNG exists and has no alpha channel.
- Local Firebase configuration remains ignored by Git. The CI plist is fake
  test configuration and must not be used for a distribution build.
- Ken approved `ITSAppUsesNonExemptEncryption = NO` for the reviewed app/Firebase
  Auth path. XcodeGen preserves it for Debug and Release; a regression test checks
  the packaged Boolean. Reassess dependencies and verify the exact RC declaration
  before upload; this means exempt encryption, not absence of encryption.

## Debug Credentials

The debug account helper no longer embeds an email/password. It appears only
when both `DAILY_WHISKERS_TEST_EMAIL` and `DAILY_WHISKERS_TEST_PASSWORD` launch
environment variables are nonempty. Set these only in a local, unshared scheme;
do not commit them or print them in build logs. The helper can create its
configured development account if Firebase reports it missing.

The helper and environment lookups remain inside `#if DEBUG`. Normal sign-in,
account creation, password reset, and request locking are unchanged.

Previously committed credentials still exist in repository history. Deleting
source literals did not retire that account; the owner's later remediation is
recorded below. No history rewrite was performed.

Initial owner disposition was to defer remediation. September 13 follow-up: Ken
confirmed that he disabled the legacy account in Firebase Console himself.
Record account retirement as complete by owner report; disabled-state/login and
token behavior were not independently verified. The agent took no Firebase
account action. See the [canonical release checklist](release-checklist.md).

## Historical Signing and Archive Verification (Superseded)

The failed attempts and retry instructions below describe the initial setup,
not actions still required. Team/device provisioning and the orientation warning
were subsequently resolved. Preserve the logs as history; use the current
[distribution procedure](distribution-readiness.md#reproduce-without-uploading)
for a newly approved RC, not these old artifacts.

The initial signed Release archive attempt failed because no development team
was configured. The owner subsequently confirmed team `HYU33CNQ69` (Kenneth
Widemon), matching the available Apple Development certificate. `project.yml`
now saves this team and automatic signing so regeneration preserves the choice.

The signed retry with `-allowProvisioningUpdates` reached Apple but failed:
the team has no registered devices from which to generate a development profile,
and no matching iOS App Development profile exists for the bundle ID. Device
discovery found only an unavailable iPad. Connect/unlock a physical iPhone or
iPad, complete trust/developer setup, and authorize registration with the team
before retrying development signing. No device was registered in this pass.
Log: `/tmp/whiskers-release-signed-team.log`.

Follow-up with the owner's connected iPhone: CoreDevice pairing succeeded, but
both generic and device-targeted archive retries still received Apple's
"no devices" / missing development-profile errors, despite enabling provisioning
updates and device registration. Local pairing is complete; Apple-side device
registration and a usable profile are not verified. No app was installed on the
phone. Logs: `/tmp/whiskers-release-signed-retry.log` and
`/tmp/whiskers-release-device-signed.log`.

The subsequent device-targeted build timed out with Xcode reporting Developer
Mode disabled on the phone. The owner must enable it on-device and complete
the restart/confirmation before a development build can use this destination.
Then retry registration/provisioning and the signed archive; enabling Developer
Mode alone does not prove the Apple-side profile issue is resolved.
Log: `/tmp/whiskers-release-device-build.log`.

Resolved after the owner enabled Developer Mode: the device-targeted Release
build succeeded with an Xcode-managed iOS Team Provisioning Profile, followed by
a successful signed Release archive at
`/tmp/whiskers-release-signed-final.xcarchive`. Strict/deep code-signature
verification passed. The archive and embedded profile identify team
`HYU33CNQ69` and application `com.example.kenwidemon.dailywhiskers`; packaged
version/build are `1.0 (1)`. Debug-helper label and environment-variable markers
are absent from the signed Release binary. No app was installed or uploaded.

This verifies development signing, not App Store distribution/export validation.
Xcode also emitted an interface-orientation warning: "All interface orientations
must be supported unless the app requires full screen." Audit the declared iPad
orientations before distribution; this retry did not change layout behavior.
Successful logs: `/tmp/whiskers-release-device-retry2.log` and
`/tmp/whiskers-release-signed-final.log`.

For packaging inspection without signing:

```sh
xcodebuild archive -project DailyWhiskers.xcodeproj \
  -scheme DailyWhiskers -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/whiskers-release-unsigned.xcarchive \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO
```

An unsigned archive is not installable/distributable evidence and does not verify
provisioning, App Store validation, or TestFlight upload. For a signed archive,
omit `CODE_SIGNING_ALLOWED=NO` after configuring the team and signing assets.

September 7 verification:

- Unsigned device Release archive succeeded. Its Info.plist contains version
  `1.0`, build `1`, and the expected bundle ID matching the packaged Firebase
  plist. Compiled `Assets.car` and daily content JSON are present.
- Release binary string inspection found none of the debug-helper button label
  or credential environment-variable names. This is a targeted exclusion check,
  not a comprehensive binary security audit.
- Dependency privacy manifests are bundled. Their presence alone does not verify
  app privacy disclosures or submission compliance; that audit is still pending.
- All 35 unit tests in four suites passed after the code/configuration changes.
  Live debug-account authentication was not exercised and no credentials were
  supplied. No UI acceptance or physical-device performance claim is added.
- Local logs: `/tmp/whiskers-release-signed.log`,
  `/tmp/whiskers-release-unsigned.log`, and `/tmp/whiskers-release-unit.log`.

## Release Handoff

Use the [canonical release checklist](release-checklist.md), not the historical
setup failures above. Initial signing, orientation configuration, metadata entry,
legacy-account retirement by owner report, reviewer preparation, and the pre-upload
account/metadata audit are no longer pending setup tasks. Final-candidate validation,
performance, account/compliance rechecks, and authorized distribution remain
separate gates. Recheck build-number
availability before uploading; the configured `1.0 (1)` is not a reserved build.
