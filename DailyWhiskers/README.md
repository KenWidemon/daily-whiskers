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
6. Add cat images to asset sets:
   - `cat_01`, `cat_02`, `cat_03`, `cat_04`, `cat_05`.

## Notes
- Any file in `DailyWhiskers/Resources/` is bundled automatically.
- App uses Firebase packages: `FirebaseCore`, `FirebaseAuth`.
