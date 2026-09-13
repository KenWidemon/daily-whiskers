# Account Lifecycle and Privacy Audit

## Status

Deletion implementation, app manifest, and source/data audit are complete for
this pass. Public privacy-policy and support pages are published and linked from
the login screen and Settings. Policy/disclosure review and the agreed live
deletion acceptance check are complete. The owner reported completing authorized
deletion and rejection of the former credentials; the agent verified signed-out
state persists after relaunch. This implementation pass is ready for commit/PR
review. Guest-first access and optional account tools were approved September 13
and are implemented with scoped iPhone acceptance passed by owner report; see the
current decision record below. This is not overall release approval,
App Store submission, or a certification of legal compliance.

## Policy Draft Inputs

### September 13 Guest-First Copy Follow-Up

Public privacy/support pages were read successfully on September 13. They still
describe account use without explaining optional entry from Settings. No public
site changes were published in this app pass. Prepare the following in the
separate site repository before release, retaining existing provider/diagnostic
disclosures and updating the policy effective date when published:

- Privacy, Account information: "You can view daily cards without an account.
  If you choose to create an account or sign in from Settings, the app uses Google
  Firebase email/password authentication. Your email address and password are sent
  to Firebase to create or authenticate your account. Firebase assigns a user
  identifier and manages authentication information. The app uses that identifier
  to recognize your signed-in session. Guest access does not create an anonymous
  Firebase account."
- Support, before sign-in help: "Do I need an account? No. Daily Whiskers opens
  directly to your daily card. Optional sign-in and account creation are available
  from Settings > Sign In. You can close sign-in and keep enjoying daily cards."
- Support, recovery: explain that guests open Settings > Sign In to reach
  Forgot password. Existing signed-in users can log out first.
- Support, deletion: begin with Settings > Sign In if needed, then Settings >
  Delete Account. Explain that successful deletion returns to guest access and
  daily cards remain available; keep permanent-deletion and retention caveats.

Guest access changes the entry flow, not the retained Firebase SDK disclosures.
Do not describe guest use as zero network activity or zero data collection.

### Previously Approved Inputs

- Operator: Kenneth Widemon (confirmed by the owner September 8, 2026).
- Public support/privacy contact: dailywhiskers.support@gmail.com (confirmed by
  the owner September 8, 2026).
- [Published privacy policy](https://kenwidemon.github.io/daily-whiskers-site/privacy/).
- [Published support page](https://kenwidemon.github.io/daily-whiskers-site/support/).
- Owner approved the presented policy and disclosures on September 8, 2026:
  "Policy and disclosure review looks good." App Store Connect metadata has not
  been submitted or independently verified.
- Both destinations returned HTTP 200 on September 8, 2026. Public site source is
  maintained separately in `KenWidemon/daily-whiskers-site`; no app configuration
  or private QA material was published with it.

## Verification

- All 44 tests in six suites passed, including verified public-link constants, deletion ordering, failed
  reauthentication, cancellation, retry, the six-operation request-lock matrix,
  and bundled email/UID privacy declarations.
- Signed Release archive succeeded at `/tmp/whiskers-account-privacy.xcarchive`.
  Strict/deep signature verification passed; the packaged app privacy manifest
  passed plist validation. Existing distribution-orientation warning remains.
- `git diff --check` passed. XcodeGen registered the new Swift files, tests, and
  privacy manifest in the explicit Xcode target build phases.
- The owner reported completing explicitly authorized live account deletion on
  September 8, 2026. The agent observed the login screen afterward and again
  after terminating and relaunching the app on iPhone 17e / iOS 26.5 Simulator.
  Evidence: `/tmp/whiskers-deletion-after.png` and
  `/tmp/whiskers-deletion-relaunch.png`. The destructive confirmation itself was
  user-operated, not directly observed by the agent. The owner subsequently
  reported "Invalid email or password." when checking the formerly working
  credentials. The agreed end-to-end acceptance check is complete; backend
  account absence was not independently inspected in Firebase Console, and a
  generic credential error alone does not prove account deletion.
- No App Store metadata submission or physical-device acceptance was performed.
- Latest build/unit run: `/tmp/whiskers-public-links-tests.log` (passed after link integration).
  Simulator was subsequently reopened for live deletion acceptance. No UI
  link-tapping acceptance was performed.
- Earlier deletion/archive logs: `/tmp/whiskers-account-privacy-final-tests.log` and
  `/tmp/whiskers-account-privacy-archive.log`.

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

## Owner Decisions / Release Blockers

1. Complete: publish public privacy-policy and support URLs and wire links into
   signed-out and signed-in screens.
2. Complete: owner approved the published policy covering operator/contact,
   account data, Firebase processing, retention, deletion, and user requests on
   September 8, 2026.
3. Guest-first access approved September 13: daily content no longer requires
   authentication on the work branch. Settings retains optional sign-in and
   signed-in logout/deletion. No anonymous Firebase account is created. Existing
   accounts and their deletion/recovery paths remain supported. Scoped iPhone
   account-transition and VoiceOver acceptance passed by owner report, including
   authorized disposable-account deletion and post-deletion guest persistence.
   Public-policy/support copy reconciliation and final-candidate repeats remain.
   Firebase SDK initialization remains; guest mode is not a claim of zero SDK
   diagnostics/network activity and does not justify removing privacy disclosures.
4. Data-use scope confirmed by the owner on September 8: only Firebase
   email/password authentication. Owner approved the presented disclosures on
   September 8, 2026. Entering and verifying the corresponding App Store Connect
   answers remains a release step; no metadata answers have been submitted.
5. Complete: live deletion was authorized and reported complete by the owner;
   signed-out state after relaunch was observed. The owner reported rejection of
   the previously working credentials with "Invalid email or password."

September 13 follow-up: Ken reported disabling the exposed legacy account in
Firebase Console. No independent rejected-login or token verification was
performed. The orientation warning was resolved in the distribution pass, and
the simulator scrolling failure was explicitly deferred after physical testing.
Use the [canonical release checklist](release-checklist.md) for current status.

## Sources

- [Apple account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app)
- [Apple Review Guidelines, privacy and account sign-in](https://developer.apple.com/app-store/review/guidelines/)
- [Firebase iOS user management](https://firebase.google.com/docs/auth/ios/manage-users)
- [Firebase Apple-platform data disclosure guidance](https://firebase.google.com/docs/ios/app-store-data-collection)
- [Firebase privacy and retention](https://firebase.google.com/support/privacy)
- [Apple privacy manifest data declarations](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest)

Reviewed September 7, 2026 against the checked-in Firebase 11.15.0 integration.
