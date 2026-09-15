# Distribution Readiness

> **RC1 archived, exported, and validated; final acceptance pending.** Updated September 14, 2026.
> The current candidate record below supersedes old artifacts for release preparation.
> The September 9 archive/export/validation and September 12 screenshot comparison
> predate VoiceOver and guest-first changes. They are not acceptance of the current
> RC and must not be used to skip checklist #6. Dated sections below describe their
> own checkpoint, not current tasks or machine state. Use the
> [release checklist](release-checklist.md) for remaining work and the
> [documentation map](README.md) for status conventions.

## Scope and Identity

This guide covers local distribution preparation, not authorization for a
TestFlight upload or App Store submission. `project.yml` is the configuration source.

- Bundle ID: `com.example.kenwidemon.dailywhiskers`, matching packaged Firebase config.
- Team: `HYU33CNQ69` (Kenneth Widemon).
- Version/build: `1.0 (1)`, unchanged. Owner reports no existing TestFlight builds.
- iOS 17 minimum; iPhone and iPad supported.
- Owner confirmed the existing record and bundle ID on September 9, 2026:
  [Daily Whiskers, app ID 6809050612](https://appstoreconnect.apple.com/apps/6809050612/distribution/ios/version/inflight).
  That initial confirmation was owner-reported; later authenticated listing
  sessions used this same record. Do not create a duplicate or rename the bundle ID.

## Release Branch Workflow

The release path is now `codex/develop` (development trunk) -> `release/rc`
(pre-release testing) -> `main` (stable release). RC is initially created from
`main`, not from the development trunk; approved trunk work enters through a
promotion PR. Build/archive/test the identified RC commit before promoting the
accepted source tree into `main`. Preserve candidate SHA/tag and artifact hashes
even when the main merge commit has a different SHA.

RC fixes must return to trunk through reviewed sync PRs. No branch creation or
promotion authorizes TestFlight upload, App Review submission, or manual release.
See [branching strategy](branching-strategy.md) for freeze, promotion, and protection
rules, and [release checklist](release-checklist.md) for current readiness.

## Orientation Configuration

The previous archive omitted supported-orientation declarations. XcodeGen now
sets explicit iPhone and iPad orientations through generated Info.plist settings.
iPhone supports portrait and both landscapes; iPad supports all four orientations.
No full-screen requirement was added. This preserves UIKit's default orientation
sets and iPad multitasking eligibility rather than suppressing the warning with
a full-screen restriction. It does not resolve the known landscape scrolling bug
or prove visual rotation/multitasking acceptance.

## RC1 Artifact Record (September 14, 2026)

- PR #46 promoted development into `release/rc` with a merge commit. Its source
  tree exactly matches reviewed develop revision
  `00f246689d876a8ff28718960b606cb40843c037`.
- Frozen commit: `20ae9cd3d664c3c412a2489ea7304449f1e0b8e2`.
  Source tree: `6391e24d23c0bb7c5026809ea4da3c77b521ef99`.
  Owner-authorized annotated tag `v1.0.0-rc.1` is published; do not move it.
  This evidence update is on a separate branch and is not part of the tagged source.
- Xcode 26.6 (17F113), iPhoneOS SDK 26.5, locked dependencies. XcodeGen reproduced
  the committed project with no diff. No toolchain/dependency migration was made
  in response to iOS 27; candidate compatibility testing remains required.
- [RC push CI](https://github.com/KenWidemon/daily-whiskers/actions/runs/34880276739)
  passed. Fresh local regression passed 57 tests in eight suites on iPhone 17e /
  iOS 26.5 simulator, signing disabled. The simulator is shut down. No full UI
  suite or new physical-device acceptance is claimed; existing deferrals remain.
- Authenticated App Store Connect inspection showed version 1.0 in Prepare for
  Submission and TestFlight's "Submit a build to start testing" empty state.
  Build 1 is currently unused by that visible inventory, not reserved; recheck
  immediately before upload. Manual release remains selected. No listing changes
  or reviewer-credential retrieval were performed.

### Local Artifacts and Verification

All paths below are relative to the repository root and are ignored by Git:

- `build/releases/v1.0.0-rc.1/DailyWhiskers.xcarchive`: signed Release archive passed.
- `build/releases/v1.0.0-rc.1/export/DailyWhiskers.ipa`: App Store export passed with
  `destination=export`, automatic signing, and no automatic version/build update.
  Size: 75,122,882 bytes, not an App Store download-size estimate.
- IPA SHA-256: `32a4bba9f7fcf63a639c558e6f800effad7a30b16ed0f19c9e8ffe5f0af2bbb4`.
- `archive-file-sha256.txt` lists archive file hashes. Its SHA-256 is
  `0e33661bed4479b032d2ecd42696eb938caa2b3058f9b54df9865781a848fe3f`.
  This identifies the recorded file-content manifest, not a hash of a directory.
- Archive and extracted IPA pass strict/deep signature verification. The export
  uses the matching iOS Team Store Provisioning Profile, expiring September 10,
  2027 UTC, with `get-task-allow=false` and no development-device list.
- Identity is `com.example.kenwidemon.dailywhiskers`, version `1.0 (1)`, minimum
  iOS 17, iPhone/iPad support, and the expected orientations. Packaged
  `ITSAppUsesNonExemptEncryption` is Boolean false, including after export.
- Packaged Firebase configuration matches the local production config semantically
  and differs from the CI fixture. Plist encoding changes during packaging; raw
  byte inequality is not a configuration mismatch. No configuration values are
  copied into these docs. App privacy declaration matches source; dependency
  privacy manifests are bundled.
- Daily JSON matches source; exported JSON and Assets.car match the archive.
  Targeted executable inspection found no test-account environment/button markers
  or screenshot/profiling-harness markers. This is not an exhaustive security audit.
- Archive executable, dSYM, and exported executable share UUID
  `9B7663E9-70C8-3AF5-A140-5EA567CD5A6D` (arm64).
- Only archive warning: skipped App Intents metadata extraction, with no App
  Intents dependency. Local unit build also reported the existing Firebase
  umbrella/module-map warning; tests passed without weakening assertions.
- Evidence in the same folder: `provenance.json`, `UnitTests.xcresult`,
  `unit-tests.log`, `archive.log`, `export.log`, and `archive-info.json`.
  Preserve these local artifacts; do not commit the IPA, profiles, or raw logs.

### App Store Validation

- After the archive-open handoff, the selected September 14, 8:38 PM archive
  showed version `1.0 (1)` and the expected bundle ID. Used **Validate App** with
  recommended App Store Connect settings, not Distribute App.
- Xcode reported **App validation complete** and **DailyWhiskers 1.0 (1)
  validated**, with "Your app successfully passed all validation checks."
  After Done, the selected archive showed Validation succeeded and the September
  14, 8:47 PM validation time. This is server validation, not App Review approval.
- Validation logs are preserved locally under
  `build/releases/v1.0.0-rc.1/validation.xcdistributionlogs`; the original log
  bundle ends in `DailyWhiskers_2026-09-14_20-45-53.644.xcdistributionlogs`.
  Original archive file-content hashes and exported IPA hash remain unchanged.
- No TestFlight build upload, distribution, or App Review submission occurred.

### RC-Source Screenshot Comparison (September 14, 2026)

- Rebuilt the existing isolated screenshot preview in Release from frozen RC
  source `20ae9cd3d664c3c412a2489ea7304449f1e0b8e2`, using locked dependencies.
  All three card builds passed; copied production Swift hashes match the RC.
  The separate entry/router and single-card manifest are preview-only: no
  Firebase configuration, live account, or shipping source was changed.
- Compared fresh Celestial, Forest, and Cozy captures against all six approved
  September 12 raw images on iPhone 17 Pro Max and iPad Pro 13-inch (M5), both
  simulator OS 26.5 at default text size. Native dimensions remain 1320 x 2868
  and 2064 x 2752 respectively.
- Scoped visual comparison passed: image crops, quote text/wrapping, vibe pills,
  frames/glow, Settings placement, and safe areas match with no visible clipping.
  Sparkle animation phase and simulator status-bar date, signal, and battery
  indicators differ. This is not a pixel-equality claim or new owner approval.
- All six approved raw images and six compositions still match saved hashes;
  none were replaced or re-uploaded. New captures, per-card provenance, and
  `comparison.json` are local under `build/releases/v1.0.0-rc.1/visual-parity/`.
- This closes the RC-source simulator screenshot comparison only, not shipping
  IPA execution, account behavior, physical acceptance, or iOS 27 compatibility.
  Status-bar overrides were cleared and both capture simulators shut down.

### Outstanding Candidate Checks

- All six approved screenshot compositions match their saved hashes; manifest,
  provider, model, and DailyRitualCardView match capture provenance. Five other
  captured auth/navigation sources differ. This static comparison does not prove
  full candidate visual parity on its own; the scoped simulator comparison above
  adds rendered evidence. Static evidence: `screenshot-source-comparison.json`.
- Exact-build device acceptance, including iOS 27 compatibility and the retained
  exact-TestFlight-candidate overnight repeat, remains open. No phone/iPad app
  was replaced during this artifact pass.
- No TestFlight upload, App Review submission, or release occurred. `main` remains
  unchanged. Accepted RC promotion to main must preserve ancestry and artifact
  provenance; this tag is not a claim that every acceptance gate has passed.

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

## Historical Local App Store Export Evidence (September 9)

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

## Historical Regression Checks (September 9)

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
For a release run, first freeze the approved `release/rc` source and record its
SHA/tag. Use fresh archive/export paths and verify version/build availability;
the sample paths below are not references to an accepted existing artifact.

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

## Historical App Store Validation and Owner Handoff (September 9)

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
This closed the archive/export/validation gate for the September 9 candidate, not App Review
or overall V1 acceptance. No TestFlight build upload or App Review submission was
performed. Those actions still require authorization. All simulators remained
shut down during validation. That implementation pass was subsequently merged.

## Screenshot Candidate Comparison (September 12, 2026)

The approved listing screenshots were statically compared with the existing
September 9 archive and exported IPA. No new archive or upload was performed.

- Candidate identity remains `1.0 (1)` with the expected bundle ID and minimum OS.
- All 31 compiled card asset records match the screenshot capture app. Archive
  and IPA asset catalogs are byte-identical, and packaged daily JSON matches
  source/capture provenance.
- Eleven captured Swift source hashes match distribution revision `e3d8575` and
  source at the September 12 comparison. No intervening shipping source or project
  changes were found then; subsequent VoiceOver/guest-first changes invalidate
  using that source comparison as current-candidate parity.
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
in the repository. Reviewer credentials and final notes were deferred at that
checkpoint; checklist #4 is now complete with owner-verified credentials and
saved/reload-verified final instructions. See the current
[listing record](app-store-listing.md). No build upload, submission, or release occurred.

## Scrolling Release Exception (September 13, 2026)

The former scrolling task (then called "step #2", **not current checklist #2**)
is complete with an owner-approved exception: Ken reported
that the complete Create Account button is reachable on the physical iPhone
in largest-text landscape, with the password keyboard remaining visible while
scrolling, and explicitly deferred the unresolved simulator failure for V1.
The existing UI test and assertions remain unchanged; the simulator suite is
not considered green. Resume simulator diagnosis after release. Installed build
identity was not reverified in this manual check, so final-candidate physical
acceptance and the broader release gates remain open. See the detailed evidence
and limitations in `accessibility-interaction-qa.md`.

## Error-focus Candidate (September 13, 2026)

Physical VoiceOver validation exposed an inline-error focus/speech failure.
A source-level fix was developed and physically checked on
`codex/physical-accessibility-acceptance`; see `accessibility-interaction-qa.md`.
Its simulator build, 48 unit tests, focused repeated-error visibility UI test,
and signed development Release build passed. Ken confirmed that the installed
fix focuses and reads the empty-email validation error, including repeat
activation. A second candidate corrects reset-alert dismissal focus; Ken confirmed
focus now returns to Forgot password, with reset loading/confirmation also passed.
The second candidate passed the same 48 unit tests, focused UI check, and signed
Release build. These scoped owner-reported passes are not full accessibility
acceptance; other VoiceOver checks remain open. Prepare and validate a new final
archive and repeat candidate/screenshot comparison before distribution: the
September 9 archive does not contain this fix. No existing distribution artifact
was overwritten or uploaded.

A third candidate moves login/reset announcements to the accepted-request
boundary after Ken reported silent sign-in speech. Its 51 unit tests, focused
UI regression, and signed Release build passed; it was installed for physical
retest. Ken confirmed sign-in speech works on this candidate. Daily-card VoiceOver
reading passed by owner report on the preceding candidate. Ken also confirmed
the reset loading/confirmation speech and dismissal-focus regression check on
the third candidate. Physical Reduce Motion also passed by owner report for
login/card decorative motion, sign-in transition, and animation resuming when
disabled. Signed-in iPhone rotation through both landscape orientations and back
to portrait, card readability/scrolling, and landscape Settings access also passed
by owner report. The rapid keyboard-submission exercise also produced no reported
visible issues; this does not measure backend request counts or prove that a
second tap reached the handler. These scoped passes do not complete broader
physical acceptance.

The same source was subsequently built and installed on the physical iPad
(`iPad16,6`, iPadOS 26.6.1) after owner enablement of Developer Mode and Xcode
provisioning updates. Ken reported passes for login and signed-in card layouts
in portrait/landscape, narrow windows and side-by-side use, keyboard/form
reachability, Settings access, and returning from a neighboring app without a
card change. These checks cover the tested text sizes/configurations, not every
Dynamic Type size or real day rollover. An isolated iPad QA app using unchanged
production logout UI then passed error-alert speech, Cancel-to-Settings focus,
and simulated Try Again recovery by owner report. The QA app and temporary
project/build files were removed, and normal Daily Whiskers was launched again.
No real account or Keychain failure was induced. Remaining acceptance items and
the limits of these results are tracked in the interaction QA notes.

## Account and Metadata Audit (September 13, 2026)

Work branch: `codex/account-metadata-readiness`, based on merged PR #43
(`9c2abe59db68d409b927ae61ee604877e5290e2b`). This is a pre-upload readiness audit,
not a new archive, legal certification, final-device pass, or submission.

### Agreements and Regional Scope

- Business shows the Free Apps Agreement as **Active**, with displayed dates
  September 5, 2026 through February 17, 2027. Paid Apps Agreement is **New**;
  no paid agreement, bank/tax setup, or legal-entity change was performed for this
  free app with no in-app purchases. Revisit if monetization changes.
- DSA initially showed Complete Compliance Requirements. Ken explicitly confirmed
  no EU distribution is planned through this developer account and authorized
  the choice "I'm not a trader under the DSA or I don't plan to distribute in the EU."
  Selected that option and saved with Done. Business then showed Digital Services
  Act status **Active**, dated September 13. No contact information was submitted
  for public DSA display. Reassess before adding EU territories or changing the
  account's distribution plans; U.S.-only availability does not remove Apple's
  declaration requirement.
- App Information still uses Entertainment/Lifestyle, not Medical/Health and
  Fitness, and the saved rating questionnaire records no medical/treatment
  information. No regulated-medical-device declaration was submitted. Vietnam
  game-license setup does not apply to the current non-game, U.S.-only scope.
- No agreement was accepted by the agent; the only account declaration changed
  was the specifically owner-approved DSA choice.

### Saved Metadata and Public Pages

- Confirmed name/subtitle, English (U.S.), bundle ID and app ID, No third-party
  content, and saved age ratings match the listing record. These observations
  do not independently establish content rights or legal compliance.
- Version 1.0 description and final review notes retain guest-first wording and
  optional reviewer access; Save is disabled and manual release is selected.
  Dedicated credentials remain owner-verified under #4; they were not retrieved.
- Three iPhone screenshots and three 13-inch iPad screenshots remain in
  Celestial, Forest, Cozy order. This is inventory verification, not a repeat of
  final-candidate screenshot parity.
- Current Price shows United States USD 0.00. Availability lists one territory,
  United States; 174 are unavailable. Public distribution is selected; Apple
  silicon Mac and Vision Pro availability remain unchecked. No pricing or
  availability changes were made.
- Privacy status is Published, with Email Address and User ID linked for App
  Functionality and Other Diagnostic Data unlinked for Analytics, consistent
  with the prior disclosure record. No privacy answers changed.
- Both public policy/support routes returned HTTP 200. Policy retains the
  September 13 date, optional-account wording, and Firebase diagnostic disclosures;
  support explains guest access and Settings sign-in. AppLinks and saved URLs
  point to these same routes. No website change was needed.

### Accessibility Claims

- App Accessibility shows **Get Started**; no support labels have been configured
  or published. Left unchanged. Apple currently describes these labels as voluntary;
  do not answer "supports none" merely because labels are not yet evaluated.
- The existing scoped VoiceOver/Reduce Motion passes are not complete evidence
  for all common tasks on each supported device. Artwork is intentionally hidden
  from accessibility with no descriptive alternative, auth retains a light
  palette, and the largest-text landscape simulator test remains deferred.
  Do not infer VoiceOver, Dark Interface, or Larger Text label eligibility from
  individual passing checks. Evaluate each desired label against Apple's criteria
  and the final candidate before publishing any claim.
- Current listing copy does not promise accessibility certification or broad
  feature support. No new accessibility claims were added to close this audit.

### Encryption Declaration

- No app-owned custom encryption implementation was found. The pinned Firebase
  Auth 11.15.0 sources use GTMSessionFetcher/NSURLSession for transport, Apple
  Security Keychain APIs for auth persistence, and CommonCrypto for SDK hashing.
  Reviewed the actual Auth target dependencies, not every product available in
  the Firebase package. This supports the proposed OS-provided/exempt encryption
  classification; it is not a claim of no encryption or an exhaustive binary audit.
- The App Information upload wizard asks about proprietary algorithms and
  standard algorithms outside/in addition to Apple's OS. Inspected those choices
  and cancelled without selecting algorithms or uploading documentation.
- Ken approved `ITSAppUsesNonExemptEncryption = NO`. Added the generated Info.plist
  setting in `project.yml` and regenerated both Debug/Release build settings.
  A new distribution test requires the packaged value to be a Boolean false,
  not a missing key or a string. The packaged Debug simulator check passed.
- Recheck the exact RC's app/dependency contents and packaged declaration before
  upload. Changes to encryption, dependencies, or functionality require renewed
  assessment. This setting does not represent Apple approval of an uploaded build.

### Verification and Remaining Gates

- Pre-upload checklist #5 is complete. `xcodebuild test` passed all 57 tests in
  eight suites on iPhone 17e / iOS 26.5 with signing disabled. The compiled Debug
  app contains `ITSAppUsesNonExemptEncryption` as Boolean false. Release device
  build settings resolve the same key to NO; this is not a Release archive check.
- Local evidence: `/tmp/whiskers-readiness-tests.log`,
  `/tmp/whiskers-readiness-tests.xcresult`, and
  `/tmp/whiskers-readiness-release-settings.log`. These temporary files are not
  committed release artifacts. Existing Firebase module/dependency-scan warnings
  and the skipped AppIntents metadata extraction remain; no test was weakened.
- The test simulator was restored to Shutdown; no simulators remain booted.
  No simulator UI or physical QA is claimed by this metadata pass; the known
  simulator deferral remains unchanged.
- No new archive, RC promotion, build upload, App Review submission, or release
  occurred. Final-candidate configuration/parity, TestFlight acceptance, reviewer
  access, and account-state rechecks remain under canonical checklist #6-#8.

Sources checked September 13:
- [Apple agreement status](https://developer.apple.com/help/app-store-connect/manage-agreements/view-agreements-status)
- [Apple DSA requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)
- [Encryption documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)
- [Encryption export guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
- [Accessibility label criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)

## References

- [Apple orientation defaults](https://developer.apple.com/documentation/uikit/uiapplication/supportedinterfaceorientations(for:))
- [Add an App Store Connect record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Validate an archive](https://help.apple.com/xcode/mac/current/en.lproj/dev37441e273.html)
- Export option names verified against the installed `xcodebuild -help`.
