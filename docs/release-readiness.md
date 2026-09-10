# Release Configuration and Security

## Current Status

September 9: account/privacy implementation and owner/live acceptance are merged
(see [account/privacy audit](account-privacy-readiness.md)). A fresh signed Release
archive passes with explicit orientations and no former orientation warning.
Local App Store export and Xcode Organizer App Store Connect validation also
passed for `1.0 (1)`; no TestFlight build upload or review submission was performed.
Distribution evidence and remaining handoff steps are tracked in
[distribution readiness](distribution-readiness.md). The earlier attempts below
are historical evidence, not the current signing/orientation status.

## Configuration

- `project.yml` is the source of truth; regenerate with `xcodegen generate`.
- Bundle ID remains `com.example.kenwidemon.dailywhiskers`. The local Firebase
  plist's `BUNDLE_ID` matches. The `example` component is not a reason to rename
  an existing Firebase registration; confirm the intended distribution identity
  before creating the App Store Connect record.
- Initial marketing version is `1.0`, build `1`. These are starting values,
  not a claim that the build number is unused in App Store Connect.
- iOS deployment target remains 17.0; iPhone and iPad remain supported.
- All 18 AppIcon slots were checked against their declared pixel dimensions;
  every referenced PNG exists and has no alpha channel.
- Local Firebase configuration remains ignored by Git. The CI plist is fake
  test configuration and must not be used for a distribution build.

## Debug Credentials

The debug account helper no longer embeds an email/password. It appears only
when both `DAILY_WHISKERS_TEST_EMAIL` and `DAILY_WHISKERS_TEST_PASSWORD` launch
environment variables are nonempty. Set these only in a local, unshared scheme;
do not commit them or print them in build logs. The helper can create its
configured development account if Firebase reports it missing.

The helper and environment lookups remain inside `#if DEBUG`. Normal sign-in,
account creation, password reset, and request locking are unchanged.

Previously committed credentials still exist in repository history. The account
owner must rotate or retire the exposed account and consider revoking existing
sessions. This change does not modify Firebase users, credentials, or sessions.
No history rewrite was performed.

Owner disposition: proceed with the repository changes without rotating or
retiring the account in this pass. Credential remediation remains open; it is
not verified complete, and no Firebase account action was taken.

## Signing and Archive Verification

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

## Remaining Owner and Release Steps

- Owner confirmed the existing App Store Connect record (6809050612), matching
  bundle ID, and no uploaded builds. Keep `1.0 (1)` and team `HYU33CNQ69`.
- Rotate or retire the previously exposed development account.
- Signed development archive, local App Store export, and Xcode Organizer
  App Store Connect validation passed for `1.0 (1)`; the orientation warning is
  resolved. The app record is owner-confirmed. No TestFlight build upload or
  App Review submission was performed.
- Account deletion, owner privacy review, public support links, and live deletion
  acceptance are complete. App Store Connect metadata entry remains outstanding.
- Keep the known phone largest-text landscape scrolling issue and physical-device
  acceptance checks tracked; this configuration pass does not resolve them.
