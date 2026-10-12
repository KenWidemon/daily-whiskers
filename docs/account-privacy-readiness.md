# Account Lifecycle and Privacy

Durable behavior and disclosure facts. The [release checklist](release-checklist.md)
records acceptance and release decisions; this document is not a legal certification.
Reassess after app, SDK, backend or business-scope changes.

## Policy and Public Pages

- Operator: Kenneth Widemon; public contact: dailywhiskers.support@gmail.com.
- [Privacy policy](https://kenwidemon.github.io/daily-whiskers-site/privacy/) and
  [support](https://kenwidemon.github.io/daily-whiskers-site/support/) are maintained
  in the separate `KenWidemon/daily-whiskers-site` repository via GitHub Pages.
- Ken approved disclosures September 8 and guest-first publication September 13.
  Site PR #1 merged as `e80df0d75607ab3d5a5824223bbd2e1f1a99fb60`; deployment and
  published bodies were verified. Policy effective date: September 13, 2026.
- Daily cards require no account. Optional Firebase email/password accounts remain;
  guests do not receive anonymous Firebase accounts. Account actions require internet.
- Guest access does not imply zero Firebase network activity or diagnostics. Do not
  remove SDK disclosures because accounts are optional.
- Signing out/deleting an account returns to guest access; bundled cards remain.
  Recovery uses Settings > Sign In > Forgot password. Backend retention and legal
  requests follow the published policy, not a promise of instantaneous backup erasure.
- App Store privacy disclosures were owner-approved, published and verified:
  Email Address and User ID linked for App Functionality; Other Diagnostic Data
  not linked for Analytics; no tracking declared. No app accessibility labels
  were published; scoped QA does not establish blanket accessibility certification.

## Account Deletion

- Settings exposes Delete Account separately from Log Out.
- The sheet explains permanence, requests the current password, and requires a
  final destructive confirmation. Submitting the keyboard alone never deletes.
- Reauthentication completes before deletion. Empty passwords and cancelled or
  failed reauthentication never issue the delete request. Passwords are not
  trimmed or logged; the view clears its password when submitted or dismissed.
- The router captures the current Firebase user and rejects a changed session
  before deleting. It does not sign into another account to perform deletion.
- Logout and deletion have separate request/feedback state, preventing deletion
  errors from appearing as logout errors. Each prevents duplicate submissions.
  Dismissal and controls are disabled while deletion is pending; failures allow
  a fresh password/retry.
- Firebase's successful `User.delete()` clears the local auth session. The router
  returns to signed-out state. The pinned SDK can report secure-storage failure
  after the remote deletion request; UI wording deliberately does not claim the
  account is intact or deletion definitely failed in that case.
- Unit-test operations are injected. Separately, the owner explicitly authorized
  deletion of their designated disposable account and reported completing the
  in-app deletion. Signed-out state persisted after relaunch. The previously
  exposed shared account was not used, and no password was collected in chat.

Firebase Auth is the only account store used by the checked-in app. There is no
Firestore, Storage, custom backend, uploaded photo, favorite, or synced history
implementation to clean up. Revisit deletion scope if those features are added;
Firebase Auth deletion alone would not delete unrelated service data.

## Data Inventory

| Data | Observed use | Disclosure follow-up |
| --- | --- | --- |
| Email and Firebase UID | Email/password authentication and routing | Linked to account; app functionality |
| Password | Submitted to Firebase Auth; transient form/request values | Describe authentication handling; never claim passwords stay only on device |
| Auth session | Firebase SDK persistence | Explain persistent sign-in and deletion/logout |
| Daily cards and local date | Bundled assets/JSON and deterministic on-device selection | No content upload or per-user content record found |
| Shared card | Locally rendered bundled artwork, quote, optional vibe, branding, and plain-text companion passed to the system share sheet | No account identifiers or source metadata; no app upload/tracking; user chooses the destination and confirms sending |
| SDK diagnostics | Firebase Auth 11.15.0 manifest declares unlinked other diagnostic data for analytics | Include SDK behavior in final App Store answers |

Only FirebaseCore and FirebaseAuth products are declared by the app target. A
package-resolution listing alone is not proof that every Firebase product is
linked or enabled. No app-level Analytics/Crashlytics, ad tracking, custom
networking, or user-content storage calls were found in this source audit.
On September 8, 2026, the owner confirmed the data-use scope is "only Firebase
email/password authentication." Scope confirmation is complete. Firebase Console
settings, external integrations, and server-side systems were not independently
inspected. This confirmation does not remove the SDK diagnostics declarations
listed above.

## Privacy Manifest

`Resources/PrivacyInfo.xcprivacy` declares the app's email and UID collection for
account functionality, linked to the user and not used for tracking. App source
does not directly use the audited required-reason API categories; the app's
accessed-API array is empty. Dependency manifests remain bundled separately.
The Firebase Auth manifest supplies its UserDefaults reason and diagnostics
declarations; an empty app-level array does not override those SDK declarations.

Manifest validity is not equivalent to legal policy approval or complete App
Store privacy answers. The final answers must combine app and SDK behavior.

## Security Decisions

Ken reported disabling the formerly embedded development account in Firebase on
September 13. This is owner-reported, not an independently observed backend/token
revocation check. Never reuse it or treat deletion of source literals as revocation.
Do not rewrite history without separate authorization. Reviewer credentials belong
only in secure credential storage and App Store Connect's dedicated fields.

## Sources

- [Apple account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app)
- [Apple Review Guidelines, privacy and account sign-in](https://developer.apple.com/app-store/review/guidelines/)
- [Firebase iOS user management](https://firebase.google.com/docs/auth/ios/manage-users)
- [Firebase Apple-platform data disclosure guidance](https://firebase.google.com/docs/ios/app-store-data-collection)
- [Firebase privacy and retention](https://firebase.google.com/support/privacy)
- [Apple privacy manifest data declarations](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest)

Reviewed September 7, 2026 against the checked-in Firebase 11.15.0 integration.
