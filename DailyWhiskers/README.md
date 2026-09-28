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
  - Create Account (email/password)
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
