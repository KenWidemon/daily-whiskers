# Daily Whiskers V1 (SwiftUI)

## Included
- `AppRouter` for Firebase auth state routing.
- `AuthView` with email/password auth (sign in + create account).
- Debug test-account shortcut in `AuthView`:
  - email: `test@dailywhiskers.app`
  - password: `WhiskersTest123!`
  - Button behavior: sign in, or create account if it does not exist.
- `DailyWhiskersView` minimal card UI with quote, image, vibe tag, and logout menu.
- Deterministic daily content selector using local day seed: `YYYYMMDD % count`.
- Local JSON content: `Resources/daily_whiskers_content.json`.

## Build in Xcode ASAP
1. Install XcodeGen once:
   - `brew install xcodegen`
2. From repo root, generate project:
   - `xcodegen generate`
3. Open the generated project:
   - `open DailyWhiskers.xcodeproj`
4. Put Firebase config at:
   - `DailyWhiskers/Resources/GoogleService-Info.plist`
   - then rerun `xcodegen generate` (it will auto-add to target resources).
5. In Firebase Console > Authentication > Sign-in method:
   - enable **Email/Password** provider.
6. Add image assets for each `imageName` used in `DailyWhiskers/Resources/daily_whiskers_content.json`
   (e.g. `arcane_spellbook_reader`, `forest_lantern_bearer`, `cozy_fireplace_sage`, etc.).

## Notes
- Any file in `DailyWhiskers/Resources/` is bundled automatically.
- `daily_whiskers_content.json` supports both the new `cards` schema and the legacy `quotes` + `imageNames` schema for backward compatibility.
- App uses Firebase packages: `FirebaseCore`, `FirebaseAuth`.
