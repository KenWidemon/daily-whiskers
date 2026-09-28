# Daily Whiskers (SwiftUI)

Daily Whiskers is an iOS SwiftUI app that shows one curated cat card per day, with optional Firebase email/password accounts.

Documentation entry point: [documentation map](../docs/README.md).
For current remaining work, use only the [release checklist](../docs/release-checklist.md);
dated QA reports preserve evidence rather than separate roadmaps.

## Current Behavior
- The daily card opens immediately without sign-in, including while Firebase restores
  its session. Guest access does not create a Firebase anonymous account.
- `AppRouter` tracks the account session; it does not gate daily content.
- Settings offers optional Sign In for guests, or Log Out and Delete Account for
  signed-in users. Privacy and Support are always available.
- Optional auth UI supports:
  - Sign In (email/password)
  - Dedicated Create Account form (email/password/confirmation)
  - Forgot password (uses the entered email; no password required)
  - Debug-only "Use Test Account"
- Daily content is selected deterministically from local date:
  - `YYYYMMDD % cards.count`
- Daily content refreshes when app returns to foreground and local day changed.
- Signed-in Settings offers password-confirmed permanent account deletion.
- Closing auth returns to the same daily card and discards unfinished credentials.
  Close/swipe dismissal is disabled while an auth request is running. Successful
  sign-in or account creation dismisses auth. Logout and deletion return to guest
  access without removing the daily card or automatically reopening sign-in.

## Dedicated Registration

Create Account opens its own form without submitting Sign In credentials. Only
trimmed email is prefilled. Sign In's password is cleared on entry; registration
passwords are cleared when leaving that form or dismissing auth. Registration
keeps its input for correction after a failed request, without persisting or
logging credentials. Password fields support AutoFill and independent visibility
controls, and mask again when the app becomes inactive. Sign In visibility remains
separate DW-006 work.

Registration validates email, password length and character types, and exact confirmation
before calling Firebase. Passwords are never trimmed. Empty/invalid submissions
show accessible feedback; navigation is available with empty Sign In fields.
Both forms retain one request lock and existing progress/error announcements.
Close and Back are disabled while a request runs; success closes auth through the
existing session listener and leaves the daily card in place.

Ken selected an Apple Account-style baseline for new accounts on September 28,
2026: at least eight characters, with an uppercase ASCII letter (A–Z), a lowercase
ASCII letter (a–z), and a number (0–9). Symbols and other Unicode characters are
allowed but not required. The existing maximum of 4096 remains. Registration
validation, visible guidance, and native [Password AutoFill rules](https://developer.apple.com/documentation/security/customizing-password-autofill-rules) use this baseline.
This is the selected length/character baseline, not a claim to reproduce Apple's
complete account security system or its common-password screening.

Length uses UTF-16 units to match [Firebase's reference policy validator](https://github.com/firebase/firebase-js-sdk/blob/main/packages/auth/src/core/auth/password_policy_impl.ts),
and confirmation compares exact UTF-8 input without Unicode normalization.
Sign In retains its existing validation so older accounts remain usable.

**Backend alignment remains pending.** The live Firebase `getPasswordPolicy`
response was rechecked September 28, 2026: minimum 6, maximum 4096, no required
character classes, enforcement `ENFORCE`. The new baseline is enforced by this
registration form, not yet by Firebase. Before shipping it as a service-wide
policy, configure Firebase's new-password requirements to minimum 8, uppercase,
lowercase, and numeric required; retain maximum 4096 and optional symbols.
Review existing-release/password-reset compatibility and preserve existing-user
sign-in before applying that live change. No Firebase settings were changed.

Registration tests use injected operations and synthetic credentials, not live
account creation. The interaction suite covers navigation, credential isolation,
local validation, visibility/background masking, and large-text reachability.
Physical VoiceOver and password-manager/AutoFill checks remain necessary; UI
hierarchy assertions do not prove speech, focus, or password-manager integration.

### DW-005 Verification (September 28, 2026)

The following runs preceded the eight-character policy revision; policy-specific
verification is recorded separately below.

- Xcode 27.0: all 65 unit tests in nine suites passed on iPhone 17 Pro / iOS 26.5.
- All eight interaction tests passed on iPad Air 11-inch (M4) / iOS 26.5,
  including both Sign In landscape checks and registration at largest text size.
- iPhone 17 Pro / iOS 26.5: guest dismissal, registration navigation/clearing,
  registration validation/visibility/background masking, and repeated reset
  validation passed. Three keyboard-dependent tests failed their software-keyboard
  precondition: the hierarchy placed the keyboard outside the screen. Temporarily
  disabling the host hardware-keyboard preference did not resolve this; the
  original preference was restored. This run is not a full phone acceptance pass.
- iPhone 17 / iOS 27.0: four targeted checks passed on a separate simulator:
  portrait keyboard navigation, landscape keyboard scrolling, registration
  largest-text scrolling, and registration validation/visibility/background masking.
- The previously deferred phone largest-text landscape test was not run or weakened.
- The first registration UI run found that UIKit replaced an existing secure entry
  when editing resumed after reveal/hide. Reinserting through the native input API
  resolved it; validation/visibility tests subsequently passed on iPad and iPhone.
- Physical VoiceOver speech/focus and password-manager/AutoFill acceptance remain
  unverified. No live account was created, no reset email was sent, and no backend
  policy, release configuration, or Xcode Cloud configuration was changed.

Local evidence (temporary artifacts, not release acceptance):
`/tmp/dw005-unit-final.log`, `/tmp/dw005-ipad-final.xcresult`,
`/tmp/dw005-iphone-final.xcresult`, `/tmp/dw005-iphone27-keyboard.xcresult`,
`/tmp/dw005-iphone27-interaction.xcresult`.
The registration screenshot is at `build/dw005/create-account-ipad.png` locally.

### Eight-Character Policy Verification (September 28, 2026)

After the policy revision, all 68 unit tests in nine suites passed on iPhone 17 /
iOS 27.0. Two focused interaction tests passed on iPad Air 11-inch (M4) / iOS 26.5:
registration validation/visibility/background masking and largest-text scrolling.
These checks cover the new minimum, each required character class, exact Unicode
confirmation, whitespace preservation, backend policy-error mapping, and retries.
Evidence: `/tmp/dw005-password-policy-unit-final.log` and
`/tmp/dw005-password-policy-ui.xcresult`. The earlier screenshots show the previous
six-character copy. Backend policy alignment and physical AutoFill/VoiceOver
acceptance remain pending.

### Physical Registration Check — Owner Report (September 28, 2026)

Ken reported that the first guided physical-device round passed, using the
iPhone 17 Pro Max selected for testing from branch `codex/dw-005-create-account`
at `a7b37a3`. The round covered opening the dedicated form, its three fields and
eight-character guidance, continuing password entry after reveal/hide without
losing text, and masking a revealed password after switching apps and returning.
Ken subsequently confirmed iOS 27 for these physical checks and approved the
guided AutoFill/password-manager round. The specific password manager and its
individual fill behavior were not reported. Ken also reported the guided
VoiceOver round passed: field/action labels and navigation, empty-form and
repeated validation-error focus/announcements, visibility-control labels,
password privacy on focus, and Back/Close accessibility. This round did not
exercise live-request progress announcements or backend failures.

These are owner-reported results on iPhone 17 Pro Max / iOS 27; the installed
binary was not independently verified. App code is unchanged from `a7b37a3`.
Larger-text physical acceptance and iPad physical coverage remain pending.
Ken deferred Firebase policy alignment; the PR remains a draft. These scoped
results supersede the earlier pending status for the checks exercised, without
closing untested acceptance criteria.

## Account and Privacy Readiness

See [account/privacy audit](../docs/account-privacy-readiness.md) for deletion
behavior, data inventory, and published privacy/support decisions. Guest-first
copy and dedicated reviewer preparation are complete; final-candidate checks
remain in the release checklist. Implementation is not release acceptance.

## Authentication Recovery

- Password reset uses Firebase's reset email flow. Confirmation is deliberately
  neutral whether the account exists or not; it does not prove email delivery.
- Sign-in, account creation, and reset share a request lock. Controls are disabled
  while a request is pending, and failures allow retry.
- Logout failures show an alert with Try Again and Cancel, retaining the daily screen.
- The debug test-account UI, credentials, and helper are excluded from Release builds.

Recovery unit tests use injected operations, not live Firebase or real email.
Before release, manually verify reset delivery to a controlled account (including
spam), login persistence after relaunch, and offline/retry behavior. A reset request
alone does not change the password; completing the emailed link does.

## Setup
1. Install XcodeGen:
   - `brew install xcodegen`
2. Generate project:
   - `xcodegen generate`
3. Open project:
   - `open DailyWhiskers.xcodeproj`

## Firebase Config
1. Place Firebase plist at:
   - `DailyWhiskers/Resources/GoogleService-Info.plist`
2. Regenerate project after adding/moving plist:
   - `xcodegen generate`
3. In Firebase Console > Authentication > Sign-in method:
   - enable `Email/Password`
4. Build and run from Xcode.

The app currently depends on:
- `FirebaseCore`
- `FirebaseAuth`

## Test Account Behavior (Debug)
In Debug builds, "Use Test Account" is visible only when both launch environment
variables `DAILY_WHISKERS_TEST_EMAIL` and `DAILY_WHISKERS_TEST_PASSWORD` are set.
Configure them in a local, unshared Xcode scheme. Never save credentials in the
shared schemes, source files, documentation, or CI logs. Leave them unset for
normal development and automated UI checks.

The helper attempts sign-in first and can create the configured account when
Firebase reports it missing. Use only a controlled development account. The
helper and its environment lookup are excluded from Release builds.

Previously embedded credentials remain in Git history. Ken reported disabling
that legacy account in Firebase Console on September 13; the agent did not
independently verify disabled state or token behavior. Do not reuse that account.

## Release Readiness

The English App Store copy and screenshot storyboard are in the
[listing record](../docs/app-store-listing.md). Approved metadata and six final
screenshots are saved in the App Store Connect version 1.0 draft. No build upload
or App Review submission has occurred.

See [release readiness](../docs/release-readiness.md) for configuration, archive
requirements and historical signing evidence. Older archives are not the current RC.
`project.yml` is the source of truth for the initial version `1.0`, build `1`.
Increment the build number before subsequent distribution uploads.

## Content Pipeline
Primary content file:
- `DailyWhiskers/Resources/daily_whiskers_content.json`

Schema:
- top-level `cards` array of objects:
  - `id` (required, unique)
  - `archetype` (required)
  - `imageName` (required)
  - `quote` (required)
  - `vibe` (optional)

Load-time integrity checks:
- JSON decode success
- required fields non-empty
- duplicate `id` rejected
- `imageName` must exist in Assets catalog
- invalid cards are dropped with integrity logging
- if no valid cards remain, app uses a built-in fallback card

Image import details:
- see `DailyWhiskers/Resources/CAT_IMAGE_IMPORT.md`

## Tests
- Step 4B behavior and manual acceptance checks are recorded in
  [Accessibility and interaction QA](../docs/accessibility-interaction-qa.md).
- Step 4A layout changes and verification limits are recorded in
  [Visual readability QA](../docs/visual-readability-qa.md).
- Unit tests live in `DailyWhiskersTests/`.
- Current suite validates:
  - JSON decode path
  - deterministic daily selection
  - fallback behavior
  - rollover expectations
  - missing-image validation behavior
  - empty/all-invalid manifests, required fields, duplicate IDs, and normalization
  - bundled manifest and asset integrity, including the fallback image
  - foreground refresh state across month/year/leap-day boundaries and missed days
  - time-zone selection and daylight-saving transitions

## Continuous Integration

The `iOS CI` GitHub Actions workflow builds the Debug simulator app and runs
unit tests on pull requests and pushes to `main`, `codex/develop`, and `release/rc`. It can
also be started manually. It uses macOS 26 and Xcode 26.6, generates the project
with XcodeGen, and selects an available iPhone simulator.

CI copies `ci/firebase-test-config.plist` into the generated app resources before
project generation. This is a fake configuration for initializing the hosted
test app, not a Firebase account or a working backend. No repository secrets
are required. These tests do not exercise real authentication; keep using your
local Firebase plist for interactive development and authentication testing.

The workflow uploads its build log and `.xcresult` bundle for seven days.
Its `Build and unit tests` check can be made required in GitHub branch rules
after the first successful run.

## Optional Interaction Tests

Select the `DailyWhiskersInteraction` scheme to run the UI checks on a dedicated,
signed-out simulator. They first verify guest entry and open Settings > Sign In.
They exercise optional-auth dismissal/relaunch, keyboard navigation and landscape form
scrolling at default and largest accessibility text sizes using empty fields,
plus repeated local validation-error visibility. The latter does not verify
VoiceOver speech or accessibility focus; those require physical acceptance.
Show the software keyboard in Simulator (I/O > Keyboard > Toggle Software
Keyboard). Tests require an on-screen, tappable keyboard key and fail clearly
when only an offscreen keyboard accessibility tree is available.
They do not create accounts, submit valid credentials, or sign out an existing
user. The scheme fails its login precondition on a signed-in device.

```sh
xcodebuild test -project DailyWhiskers.xcodeproj \
  -scheme DailyWhiskersInteraction \
  -destination 'platform=iOS Simulator,id=YOUR_QA_SIMULATOR_ID' \
  -parallel-testing-enabled NO -onlyUsePackageVersionsFromResolvedFile
```

Use the normal signed development build and a local Firebase configuration.
The existing `DailyWhiskers` unit-test scheme and CI job are unchanged. The UI
suite restores portrait orientation and passes text size as a launch argument,
rather than changing the simulator's persistent accessibility preference.

Historical baseline: the three keyboard/scrolling UI checks passed on iPad Air
11-inch (M4). The Pro Max largest-text landscape simulator failure remains
unresolved and was explicitly deferred for V1 after an owner-reported physical
scrolling pass. Keep that test and its assertions unchanged. The new validation
check is tracked separately;
see [interaction QA](../docs/accessibility-interaction-qa.md). This optional scheme
is not yet a fully green phone acceptance gate.

## Public Privacy and Support

- [Privacy policy](https://kenwidemon.github.io/daily-whiskers-site/privacy/)
- [Support](https://kenwidemon.github.io/daily-whiskers-site/support/)
- Contact: dailywhiskers.support@gmail.com. Operator: Kenneth Widemon.

Both destinations are accessible from optional sign-in and from Settings for
guests and signed-in users. Public site source is maintained separately in
`KenWidemon/daily-whiskers-site` and deployed through GitHub Pages.

## Branch / PR Workflow
Canonical remaining release steps and owner decisions:
[V1 release checklist](../docs/release-checklist.md). Keep its item numbers and
statuses updated as work proceeds; skipped items are not automatically waived.

Local archive/export steps and Apple account handoff:
[Distribution readiness](../docs/distribution-readiness.md).

Performance findings and remaining device checks: [Step 5 QA](../docs/performance-qa.md).

Branch roles:
- `main`: stable release branch.
- `codex/develop`: development trunk for approved work, including work for later releases.
- `release/rc`: long-lived pre-release testing branch, initially created from
  `main`. It receives approved development snapshots through promotion PRs.
- `codex/<task>`: one task branch per roadmap item, created from `codex/develop`
  (for example, `codex/ci-baseline`).
- `codex/rc-<fix>`: release-fix branch created from `release/rc`, targeting RC
  first; bring every accepted fix back into the development trunk through a PR.

Expected flow per item:
1. Create a `codex/<task>` branch from the updated `codex/develop` branch.
2. Implement and verify one item only.
3. Get Ken's sign-off.
4. Commit, push, and open a PR into `codex/develop`.
5. Merge the approved PR before starting the next item.
6. When release scope is approved, promote `codex/develop` into `release/rc`
   through a PR. Freeze the candidate; do not automatically pull in later trunk work.
7. Test, archive, and validate the RC commit; record its tag, version/build, and
   artifact provenance. Any candidate change requires renewed relevant validation.
8. Promote the accepted `release/rc` into `main` through a release PR. Use merge
   commits for promotions between long-lived branches to preserve ancestry.
9. Keep `release/rc` and `codex/develop` synchronized with released fixes through
   PRs. App Store upload, review submission, and manual release remain separately
   authorized actions.

See [branching strategy](../docs/branching-strategy.md) for promotion, freeze,
fix propagation, candidate identity, and branch-protection expectations.
