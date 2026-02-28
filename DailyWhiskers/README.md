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
4. Build and run from Xcode.

## Firebase Config
1. Place Firebase plist at:
   - `DailyWhiskers/Resources/GoogleService-Info.plist`
2. Regenerate project after adding/moving plist:
   - `xcodegen generate`
3. In Firebase Console > Authentication > Sign-in method:
   - enable `Email/Password`

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

## Branch / PR Workflow
Team convention is one branch per roadmap item:
- naming: `pass-<n>-item-<n>-<slug>`
- example: `pass-1-item-3-day-rollover-behavior`

Expected flow per item:
1. branch from `codex/develop`
2. implement one item only
3. sign-off
4. commit and open PR to `codex/develop`
5. merge PR before starting next item
