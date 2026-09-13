# Distribution Readiness

## Scope and Identity

This pass prepares local distribution artifacts, not a TestFlight upload or App
Store submission. `project.yml` remains the source of truth.

- Bundle ID: `com.example.kenwidemon.dailywhiskers`, matching packaged Firebase config.
- Team: `HYU33CNQ69` (Kenneth Widemon).
- Version/build: `1.0 (1)`, unchanged. Owner reports no existing TestFlight builds.
- iOS 17 minimum; iPhone and iPad supported.
- Owner confirmed the existing record and bundle ID on September 9, 2026:
  [Daily Whiskers, app ID 6809050612](https://appstoreconnect.apple.com/apps/6809050612/distribution/ios/version/inflight).
  These account-side details are owner-reported, not an independently inspected
  authenticated record. Do not create a duplicate or rename the bundle ID.

## Orientation Configuration

The previous archive omitted supported-orientation declarations. XcodeGen now
sets explicit iPhone and iPad orientations through generated Info.plist settings.
iPhone supports portrait and both landscapes; iPad supports all four orientations.
No full-screen requirement was added. This preserves UIKit's default orientation
sets and iPad multitasking eligibility rather than suppressing the warning with
a full-screen restriction. It does not resolve the known landscape scrolling bug
or prove visual rotation/multitasking acceptance.

## Local Archive Evidence (September 9, 2026)

- Xcode 26.6 (17F113), iPhoneOS SDK 26.5.
- Signed Release archive succeeded: `/tmp/whiskers-distribution-20260909.xcarchive`.
- Strict/deep code-signature verification passed.
- Packaged `UISupportedInterfaceOrientations~iphone` and `~ipad` contain the
  expected three/four orientations. The former orientation warning is absent.
- Packaged identity is `1.0 (1)` with the expected bundle ID and Firebase match.
- `Assets.car`, daily JSON, app privacy manifest, and dependency manifests are
  bundled. App manifest passes plist validation.
- Release executable contains no debug test-account label/environment markers.
- The only archive warning found was skipped App Intents metadata extraction
  because no AppIntents framework dependency exists; the app has no App Intents.
- Archive log: `/tmp/whiskers-distribution-20260909-archive.log`.
- Development signing is not distribution-signing or server-validation evidence.

## Local App Store Export Evidence

- Initial export without provisioning updates failed for lack of a matching
  distribution profile. The retry with `-allowProvisioningUpdates` succeeded.
- IPA: `/tmp/whiskers-distribution-20260909-export/DailyWhiskers.ipa`.
- Xcode's `DistributionSummary.plist` identifies Cloud Managed Apple Distribution
  signing and an iOS Team Store Provisioning Profile, expiring September 9, 2027.
- Extracted IPA passes strict/deep code-signature verification. Its embedded
  profile matches the team/bundle ID and has `get-task-allow=false`.
- Version/build remain `1.0 (1)`. No TestFlight/App Store upload was performed.
- Logs: `/tmp/whiskers-distribution-20260909-export.log` (initial failure) and
  `/tmp/whiskers-distribution-20260909-export-provisioning.log` (success).
- App Store Connect validation passed through Xcode Organizer's **Validate App**
  action on September 9, 2026. See validation evidence below.

## Regression Checks

- Final build/unit run passed: 46 tests in seven suites, including two packaged-orientation tests.
  Tests read the raw plist because `Bundle.infoDictionary` resolves idiom-specific
  keys on the running device. An initial test incorrectly used that resolved
  dictionary for the other idiom; correcting the test resolved the failure.
- Test log: `/tmp/whiskers-distribution-20260909-tests-final.log`.
- All simulators were shut down after verification. No physical-device or
  rotation UI acceptance was performed in this pass.

## Reproduce Without Uploading

Run from the repository root with the ignored, real Firebase plist installed.
Never distribute the CI fixture plist.

```sh
xcodegen generate
xcodebuild archive -project DailyWhiskers.xcodeproj \
  -scheme DailyWhiskers -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/whiskers-distribution.xcarchive \
  -onlyUsePackageVersionsFromResolvedFile

xcodebuild -exportArchive \
  -archivePath /tmp/whiskers-distribution.xcarchive \
  -exportOptionsPlist ci/ExportOptions-AppStore.plist \
  -exportPath /tmp/whiskers-distribution-export \
  -allowProvisioningUpdates
```

The export plist explicitly sets `destination=export`, automatic signing, and
`manageAppVersionAndBuildNumber=false`. It does not upload or silently change the
build number. Provisioning updates may obtain signing assets through the Xcode
account. Export success alone is not App Store validation or review approval.

## App Store Validation and Owner Handoff

The existing app record and lack of uploaded builds are owner-confirmed. Use the
existing identity and `1.0 (1)`; do not create a new record or change its SKU.
Confirm required agreements yourself; the agent does not accept legal terms on
your behalf.

An initial CLI attempt using `method=validation`
and `destination=export` failed before validation: Xcode requires `upload` for
that combination. The destination was not changed; no build was uploaded.
Log: `/tmp/whiskers-validation-20260909.log`.

After the owner unlocked the Mac, the agent opened the September 9 archive in
Xcode Organizer and selected **Validate App**, not **Distribute App**. The selected
archive showed `1.0 (1)` and `com.example.kenwidemon.dailywhiskers`. Recommended
validation settings were used. Xcode reported **App validation complete** and
**DailyWhiskers 1.0 (1) validated**, with the message:
"Your app successfully passed all validation checks."

Local Xcode evidence is in
`/var/folders/kl/7606x4hd1j5bv19c_lmxgmcr0000gn/T/DailyWhiskers_2026-09-09_21-58-28.726.xcdistributionlogs`.
This closes the archive/export/validation gate for this candidate, not App Review
or overall V1 acceptance. No TestFlight build upload or App Review submission was
performed. Those actions still require authorization. All simulators remained
shut down during validation. Changes are prepared for PR review into `codex/develop`.

## Screenshot Candidate Comparison (September 12, 2026)

The approved listing screenshots were statically compared with the existing
September 9 archive and exported IPA. No new archive or upload was performed.

- Candidate identity remains `1.0 (1)` with the expected bundle ID and minimum OS.
- All 31 compiled card asset records match the screenshot capture app. Archive
  and IPA asset catalogs are byte-identical, and packaged daily JSON matches
  source/capture provenance.
- Eleven captured Swift source hashes match distribution revision `e3d8575` and
  current source. No intervening shipping source or project changes were found.
- IPA executable UUID matches the archive dSYM; strict/deep signature verification
  passed outside the sandbox. The initial sandbox attempt could not establish
  certificate trust; no trust settings or signing assets were changed.
- Packaged Firebase config matches the local real config, not the CI fixture.
  No targeted screenshot-only/debug-helper markers were found in the executable.
- Six approved composition files remain unchanged. Local evidence, including
  the IPA hash, is `build/screenshots/2026-09-12/candidate-comparison.json`.

This closes the static screenshot comparison for this candidate, not physical
acceptance, current server-side validation, or upload authorization. Repeat the
comparison after UI/content/candidate changes. See the
[approved listing and screenshot record](app-store-listing.md).

## Listing Entry (September 12, 2026)

After owner authorization and sign-in, approved English (U.S.) listing copy,
name/subtitle, Entertainment/Lifestyle categories, and support/privacy URLs were
saved in the existing app record. Three 6.9-inch iPhone and three 13-inch iPad
screenshots were uploaded and verified in Celestial, Forest, Cozy order.

The version remains `Prepare for Submission`. No build upload, build selection,
or App Review submission occurred. Reviewer access, pricing/availability, and regulatory decisions remain
separate tasks. Existing automatic release behavior was not changed.
See the [listing entry record](app-store-listing.md#app-store-connect-entry).

Follow-up: Ken confirmed `2026 Kenneth Widemon` and ChatGPT-generated artwork/
quotes with no third-party photos, artwork, or copied quotations used as inputs.
Copyright and the `No third-party content` answer were saved and verified after
reload. These owner-confirmed metadata entries do not establish independent legal
clearance or close any remaining privacy, age-rating, or physical acceptance gate.

Privacy follow-up: Ken approved the three disclosure categories and explicitly
accepted Apple's final publication agreement. Published and verified the
authenticated status on September 12: email and user ID linked for App
Functionality; Other Diagnostic Data unlinked for Analytics; no tracking for all
three. This completes privacy-label publication, not build or review submission.

Age-rating follow-up: after owner approval, saved the questionnaire with no
higher-age override and no Made for Kids enrollment. Verified 9+ in 172 countries
or regions, 12+ in Vietnam/Brazil, and All in Korea; earlier-than-26 operating
systems show global 4+ with regional exceptions. The App Information page also
showed a content-rights setup prompt despite the previous saved/read-back record;
the subsequent recheck found no selected answer. Restored the owner-approved No
answer, saved the parent page, and verified persistence after reload.

Reviewer/distribution follow-up (September 13): owner-approved free pricing is
verified at USD 0.00, with only the United States available on app release.
Mac/Vision Pro availability is disabled and manual release is saved. Public
distribution remains selected. Approved review contact name/email and the phone
Ken entered directly are present with Save disabled; no phone value is recorded
in the repository. Dedicated reviewer credentials and final review notes remain
deferred. No build upload, review submission, or release occurred. See the
prepared notes and detailed evidence in `app-store-listing.md`.

## References

- [Apple orientation defaults](https://developer.apple.com/documentation/uikit/uiapplication/supportedinterfaceorientations(for:))
- [Add an App Store Connect record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Validate an archive](https://help.apple.com/xcode/mac/current/en.lproj/dev37441e273.html)
- Export option names verified against the installed `xcodebuild -help`.
