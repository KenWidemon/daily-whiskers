# Release Configuration and Security

Configuration guide, not a second release roadmap. See the
[release checklist](release-checklist.md) for status and the
[distribution record](distribution-readiness.md) for frozen candidate evidence.

## Configuration

- `project.yml` is the source of truth; regenerate with `xcodegen generate`.
  Use CI's pinned XcodeGen 2.46.0. The post-generation hook preserves the existing
  Associated Domains dictionary when that version stringifies nested target
  attributes. Unknown capability metadata fails generation; review it rather than
  changing entitlements or signing settings to work around a generation error.
- Bundle ID remains `com.example.kenwidemon.dailywhiskers`. The local Firebase
  plist's `BUNDLE_ID` matched during the release audit; verify your local copy.
  The `example` component is not a reason to rename
  an existing Firebase registration. The existing App Store Connect record is
  `6809050612`; do not create a duplicate or rename its confirmed bundle ID.
- Prepared marketing version is `1.2`, build `4`; accepted V1.1 remains `1.1 (3)`
  and frozen V1 remains `1.0 (1)`.
  Configuration does not reserve the build number in App Store Connect or prove
  archive, signing, upload, or release readiness. Recheck availability before upload.
- V1.2 requires iOS/iPadOS 26.2 or later; iPhone and iPad remain supported.
  Earlier OS versions are outside V1.2 support. This policy does not change frozen
  releases or turn unresolved iOS 17 results into passing evidence. Verify the built
  `MinimumOSVersion` and qualify the exact 26.2 runtime separately from newer-OS tests.
- All 18 AppIcon slots were checked against their declared pixel dimensions;
  every referenced PNG exists and has no alpha channel.
- Local Firebase configuration remains ignored by Git. The CI plist is fake
  test configuration and must not be used for a distribution build.
- Password AutoFill uses `webcredentials:daily-whiskers.web.app`. XcodeGen
  supplies the Associated Domains capability and entitlement for Debug and Release.
  Signing profiles must authorize Associated Domains; verify the signed app's
  application identifier against the host's `/.well-known/apple-app-site-association`
  response before distributing a build.
  This domain configuration does not establish successful on-device AutoFill.
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

## Packaging Boundaries

- XcodeGen controls explicit iPhone portrait/landscape and iPad all-orientation
  declarations. Do not suppress rotation testing by making the app full-screen-only.
- Keep README/import instructions outside bundled Resources. Regenerate the Xcode
  project after moving resource files and review the whole generated diff.
- Do not ship fixture Firebase config, preview/profiling harnesses, debug helpers,
  credentials, traces or documentation as app resources.
- Build 1 is already uploaded. A replacement binary needs a new unused build
  number and renewed relevant checks; do not change the immutable RC1 tag.
- Development registration policy changes are not permission to alter live Firebase
  settings. See [DW-005 acceptance limits](testing.md#dw-005-development-evidence).

## Rehearsal Security Boundary

The [offline release rehearsal](distribution-readiness.md#offline-release-policy-rehearsal)
uses synthetic configuration and inspection records. Never supply real Firebase
configuration, credentials, archives or IPAs to its fixtures or public reports.
Its `release_eligible=false` result is unconditional. Fixture signature/profile
claims are not a check of current signing assets, and its temporary ledger does
not reserve a build in App Store Connect.

The rehearsal workflow has only a read-only repository token, no environment or
release secrets, and no signing/upload adapter. Keep production adapters and
credential/environment settings out of this stage. Future privileged work needs
separate ownership and settings approval, private artifact storage and verified
package-specific approval. Existing automatic signing/export remains the manual
path; the rehearsal does not enable provisioning or change distribution settings.
