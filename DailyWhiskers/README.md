# Daily Whiskers (SwiftUI)

Daily Whiskers is an iOS SwiftUI app that shows one curated cat card per day with Firebase email/password auth.

## Current Behavior
- Auth routing lives in `AppRouter`.
- Auth UI supports:
  - Sign In (email/password)
  - Create Account (email/password)
  - Debug-only "Use Test Account"
- Daily content is selected deterministically from local date:
  - `YYYYMMDD % cards.count`
- Daily content refreshes when app returns to foreground and local day changed.

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
In debug builds, `AuthView` includes "Use Test Account":
- email: `test@dailywhiskers.app`
- password: `WhiskersTest123!`
- behavior: attempts sign-in first; if user is not found, creates the account.

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
- invalid cards are dropped with debug logging
- if no valid cards remain, app uses a built-in fallback card

Image import details:
- see `DailyWhiskers/Resources/CAT_IMAGE_IMPORT.md`

## Tests
- Unit tests live in `DailyWhiskersTests/`.
- Current suite validates:
  - JSON decode path
  - deterministic daily selection
  - fallback behavior
  - rollover expectations
  - missing-image validation behavior

## Continuous Integration

The `iOS CI` GitHub Actions workflow builds the Debug simulator app and runs
unit tests on pull requests and pushes to `main` and `codex/develop`. It can
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

## Branch / PR Workflow
Branch roles:
- `main`: stable release branch.
- `codex/develop`: integration branch for approved work.
- `codex/<task>`: one task branch per roadmap item, created from `codex/develop`
  (for example, `codex/ci-baseline`).

Expected flow per item:
1. Create a `codex/<task>` branch from the updated `codex/develop` branch.
2. Implement and verify one item only.
3. Get Ken's sign-off.
4. Commit, push, and open a PR into `codex/develop`.
5. Merge the approved PR before starting the next item.
6. When ready for release, promote `codex/develop` into `main` through a release PR.
