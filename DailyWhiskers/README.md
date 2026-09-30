# Daily Whiskers (SwiftUI)

Daily Whiskers is an iOS SwiftUI app that shows one curated cat card per day, with optional Firebase email/password accounts.

Documentation entry point: [documentation map](../docs/README.md).
For current remaining work, use only the [release checklist](../docs/release-checklist.md);
testing guidance preserves scoped evidence and open risks, not separate roadmaps.

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

Verification and remaining DW-005 acceptance limits are summarized in
[testing](../docs/testing.md#dw-005-development-evidence). Detailed execution
discussion belongs in [DW-005](https://github.com/KenWidemon/daily-whiskers/issues/54)
and [PR #69](https://github.com/KenWidemon/daily-whiskers/pull/69).

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
screenshots are saved in App Store Connect. V1 build 1.0 (1) was uploaded and
submitted; use the release checklist for the latest owner-reported resubmission
and remaining approval gates.

See [release readiness](../docs/release-readiness.md) for configuration, archive
requirements and credential safeguards. Older archives are not the current RC.
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
- See [content pipeline](../docs/content-pipeline.md).

## Tests
- Repeatable acceptance checks and evidence limits: [testing](../docs/testing.md).
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

Run the unit suite on an available dedicated simulator after configuring Firebase
and regenerating the project (CI uses the fake fixture described below):

```sh
xcodebuild test -project DailyWhiskers.xcodeproj \
  -scheme DailyWhiskers \
  -destination 'platform=iOS Simulator,id=YOUR_QA_SIMULATOR_ID' \
  -parallel-testing-enabled NO -onlyUsePackageVersionsFromResolvedFile
```

## Continuous Integration

The `iOS CI` workflow runs on every PR targeting `main`, `codex/develop`, or
`release/rc`, pushes to those branches, and manual dispatch. Its final **CI Gate**
checks the actual results of classification, documentation/policy checks, and the
app job. Only a successful docs-only classification permits the app job to skip.
A failed, cancelled, timed-out, missing, or unexpectedly skipped prerequisite
cannot pass the gate. Workflow-level path filters are deliberately absent.
A whole-run cancellation or service outage can prevent the gate from executing;
required-check enforcement must leave that PR blocked, never treat it as a pass.

Documentation-only means changes exclusively to `docs/**/*.md`, `AGENTS.md`,
`DailyWhiskers/README.md`, `ci/screenshots/README.md`, or the PR template. Renames
consider both old and new paths. Empty, unknown, or unreadable comparisons take
the full path. Scripts, workflow/configuration files, dependency locks, source,
tests, and resources require app validation. Pushes/manual runs always validate
the app. Classification uses the PR base/head merge-base; validation checks out
GitHub's proposed merge commit.

### Documentation and policy checks

Every run checks Markdown formatting, repository-relative links and Markdown
heading anchors across tracked documentation. Tools parse Markdown without
executing embedded content or fetching external URLs. External URL availability
is outside this deterministic gate. Paths and symlinks cannot leave the checkout.
The formatting rules preserve existing prose conventions; this is not a rewrite
of the documentation. CI also lints workflows and tests classification, gate
results, and the link checker.

```sh
python3 -m unittest discover -s ci -p 'test_*.py' -v
npm ci --ignore-scripts --prefix ci/checks
npm test --prefix ci/checks
npm run check --prefix ci/checks
```

Node 24.12.0 and the documentation tool lockfile define the check environment.
`npm ci --ignore-scripts` does not execute dependency lifecycle scripts. Tool
updates must update the lockfile and pass the checks in the same PR.

### App validation and pinned inputs

The app job uses the `macos-26` ARM64 runner, Xcode **26.6 / 17F113**, the iOS
simulator SDK 26.5, and **iPhone 17 Pro / iOS 26.4.1**. It verifies Xcode and the
exact simulator rather than falling back to another installation. Runner image,
architecture, Swift/SDK versions, and simulator identity are logged. Hosted
runner images remain mutable; reproducibility means pinned inputs with explicit
drift failures, not byte-identical signed artifacts.

XcodeGen **2.46.0** is downloaded from its release and checked against a committed
SHA-256. Actions use full commit SHAs with release comments; actionlint **1.7.12**
is checksum-verified. When updating tools, verify upstream release identity,
change the version/hash together, and rerun both cold and warm validation.

CI copies `ci/firebase-test-config.plist` into the app resources before project
generation. This fake fixture initializes the hosted test app without live
Firebase access. PRs receive only `contents: read`, checkout does not persist
credentials, and no release secrets are used. App validation runs the Debug
build and unit suite with signing disabled. It does not replace live auth,
interaction, physical accessibility, or release acceptance.

### SwiftPM cache and lock enforcement

The committed `Package.resolved` must exist and remain byte-for-byte unchanged
after project generation, dependency resolution, and tests. Resolution/build
use `-onlyUsePackageVersionsFromResolvedFile` and
`-disableAutomaticPackageResolution`. Dependency upgrades require an intentional
lockfile change in the PR; a cache hit never substitutes for resolution or tests.

Only `build/SourcePackages` is cached. Keys include OS, architecture, Xcode build,
simulator SDK platform/version, lockfile hash, and a cache epoch. There are no
broad restore keys and no DerivedData products, credentials, or Firebase config
in the cache. A cache is saved only after successful app validation. GitHub scopes
PR caches to the PR merge ref, so untrusted PR runs cannot populate the base
branch's shared cache. Manual runs use their selected branch's cache scope.

For a cold/warm comparison, dispatch the same commit twice with a fresh, identical
`cache_epoch` value. The first must report a miss; the second must report a hit.
Use the same runner/tool configuration and compare the job summaries for
resolution, build/test, and combined seconds. Record actual measurements and run
links in the issue/PR, not a promised speedup or a README execution journal.
Changing the epoch safely abandons an old cache without deleting evidence.

The app timeout remains 30 minutes; smaller jobs have explicit timeouts.
Concurrency cancels superseded runs for the same PR/ref. Logs, timing summaries,
and `.xcresult` bundles are uploaded when available, including failure paths,
with seven-day retention. Hard termination can prevent artifact upload; missing
artifacts are not proof of success.

### Gate verification and rollout

Before requiring CI Gate, exercise docs-only, app-only, mixed, and workflow-only
PR changes, plus broken links/tests, lock enforcement, timeout, cancellation,
unknown paths, and unexpected skips. Use disposable proof branches if the new
workflow is not yet on a target branch; clearly distinguish that evidence from
actual target-branch enforcement. Do not merge deliberate failures. Reruns and
manual dispatch are useful diagnostics but do not replace real PR-event proof.

Ruleset configuration and recovery are governed by the
[branching strategy](../docs/branching-strategy.md#ci-and-protection). The workflow
alone does not protect branches. A passing workflow PR does not complete ruleset
rollout or authorize any release.

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
see [testing](../docs/testing.md). This optional scheme
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

Performance risks and scoped evidence: [testing](../docs/testing.md#v1-deferrals-and-performance-evidence).

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
