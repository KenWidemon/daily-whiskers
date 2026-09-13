# V1 Manual Release Checklist

Canonical remaining-work list, established September 13, 2026. Maintain this
file as work proceeds; preserve item numbers when checking items off or recording
explicit deferrals. Detailed QA documents are evidence, not competing roadmaps.
Skipping to an item does not waive earlier items. No upload, submission, or manual
release is authorized merely by approval of this checklist.

## Completed Baseline

- PR #41 merged into `codex/develop`: guest-first access, optional account tools,
  56 passing unit tests, four focused UI checks, signed Release build, and scoped
  owner-reported iPhone account-transition/VoiceOver acceptance. RC promotion has
  not occurred; `release/rc` was created from the stable `main` baseline.
- PR #40 merged into `codex/develop`: VoiceOver fixes, tests, and scoped physical
  iPhone/iPad acceptance. Latest unit suite: 51 tests in seven suites passed;
  focused error-visibility UI check and signed device builds passed.
- Listing copy, six screenshots, content rights, privacy disclosures, age ratings,
  review contact, and free/U.S.-only/iPhone-and-iPad/manual-release settings were
  entered and verified. Recheck before submission; no uploaded build is recorded.
- Temporary logout QA app/project/build files were removed after acceptance.
- Largest-text landscape simulator diagnosis is explicitly deferred until after
  V1 by Ken. Keep the test/assertions intact; do not treat the suite as green or
  silently reintroduce this as a release blocker.

## Remaining Steps

1. **Passed on the tested iPhone; final-candidate repeats remain.** The scoped
   guest-first VoiceOver checks passed by owner report, including backend-error
   focus, reset focus, account creation, deletion warning/cancellation/completion,
   and sign-in/logout with Reduce Motion. Preserve the evidence below and repeat
   key checks on the final distributed candidate; this is not all-device coverage.
2. **Open: finish a bounded performance pass.** Natural cold launch, real local-
   day/foreground refresh, memory-pressure behavior, and observed animation hitches
   remain unresolved. Explicitly defer or schedule longer energy/session and
   lower-memory-device testing. Do not repeat the failed Instruments launch path
   as though it establishes natural launch timing.
3. **In progress: resolve security/product decisions.** Legacy development account
   disabled in Firebase Console by owner report; independent disabled-state/login
   verification has not been performed. Ken confirmed Danny's approval of guest-
   first access and optional account tools. Implementation and automated checks
   pass, as does the scoped physical iPhone transition/VoiceOver pass by owner
   report. Published-copy reconciliation remains; final-candidate retesting is
   tracked separately under #1 and #7.
4. **Deferred by owner: complete reviewer access.** If account features remain,
   create/verify a dedicated review account, enter its credentials directly in
   App Store Connect, and finalize review notes. Reassess requirements after #3;
   do not use the owner's personal account or commit credentials.
5. **Open: confirm account/metadata readiness.** Verify Apple agreements and
   applicable compliance/export questions, public support/privacy URLs, and saved
   listing settings. Accessibility claims must match verified support. Reconcile
   listing/privacy/reviewer copy with any product changes from #3.
6. **Open: prepare the final release candidate.** `release/rc` starts from `main`;
   promote the approved `codex/develop` snapshot into RC through a PR, then freeze
   and identify the candidate commit/tag. Rerun regression tests; archive, export,
   and validate that exact RC candidate. Promote the accepted RC to `main` through
   a release PR, preserving its tested source tree and artifact provenance. Verify
   production Firebase configuration if retained, version/build availability,
   and screenshot parity. The September 9 archive predates the VoiceOver fixes.
7. **Not started: upload to TestFlight and test that exact build.** With upload
   authorization, verify installation, daily content, session persistence,
   account creation/sign-in/reset/deletion if retained, and key accessibility/
   layout behavior on iPhone and iPad. Include guest behavior if implemented.
8. **Not started: submit for App Review.** Select the tested build, verify
   reviewer access/metadata, retain manual release, and submit only with Ken's
   authorization. Address review feedback and retest any resulting changes.
9. **Not started: manually release after approval.** At Pending Developer Release,
   perform the final go/no-go check. Release only with Ken's explicit approval.

## Item 3 Decision Record

Ken selected #3 on September 13. Items #1 and #2 remain open, not waived.
Work branch: `codex/release-security-decisions`, based on merged `codex/develop`.

### Legacy Development Account

- Historical source identifies `test@dailywhiskers.app`. Only the email was
  retrieved for this audit; the password was not printed or copied.
- Current source uses local debug environment variables, but removing source
  literals did not invalidate historical credentials.
- Owner action complete: Ken confirmed on September 13 that he disabled the
  legacy account himself in Firebase Console. Record this as owner-reported
  remediation, not an independently verified console state or rejected-login test.
- The agent did not change Firebase accounts/sessions or retrieve credentials.
  No separate manual token-revocation action or token inspection was reported.
  Do not re-enable this account or configure it as the reviewer account.
- Do not rewrite Git history without separate approval. Issued ID tokens and
  cached local auth state must not be assumed to disappear instantly after a
  server-side account change.

### Guest Access

- Approved September 13: Ken confirmed Danny's decision to make sign-in and
  account tools optional. This supersedes the earlier guest-access deferral.
- Implemented on the work branch: open directly to the daily card without authentication; retain
  optional account entry in Settings and existing-user deletion/recovery access.
- Guest use should not create a Firebase anonymous user or invent an account
  benefit. Auth-only controls must reflect actual signed-in state.
- Implementation includes routing/session behavior, optional auth
  dismissal, Settings states, sign-out/deletion return behavior, regression tests,
  accessibility checks, and corresponding listing/review/privacy documentation.
- Firebase email/password accounts remain supported; removing all authentication
  is not approved scope. No account sync, saved favorites, or other new benefit
  is implied by an optional account.
- Local listing/review copy is being revised; saved App Store Connect metadata
  and the separate public site have not been changed in this pass.
- Ken also requested removal of the extra Hide Keyboard toolbar button. Native
  keyboard submission, interactive scroll dismissal, and auth Close remain.
- Verification complete on the work branch: 56 unit tests in eight suites,
  four focused UI checks on iPhone 17e / iOS 26.5 Simulator, and a signed Release
  device build passed. UI coverage includes guest card/relaunch, optional auth
  Close/reopen, default portrait keyboard navigation without Hide Keyboard,
  default landscape scrolling, and repeated local error visibility. This is not
  an archive, upload, real-account transition test, or physical VoiceOver pass.
- Evidence: `/tmp/whiskers-guest-verified-tests.xcresult`,
  `/tmp/whiskers-guest-verified-ui.xcresult`,
  `/tmp/whiskers-guest-verified-release.log`, and
  `/tmp/whiskers-guest-verified-source-hashes.txt`. Source hashes were rechecked
  after the run. The authorized temporary simulator hardware-keyboard change was
  restored and the QA simulator shut down. No replacement of the approved
  screenshot exports occurred in this pass.
- Physical follow-up: the tested signed Release build was installed over the
  existing app on iPhone 17 Pro Max, preserving data/session. Signature validation
  and launch command succeeded; binary hash is recorded in
  `/tmp/whiskers-guest-physical-binary-hash.txt`. Ken confirmed guest state with
  VoiceOver initially off. After enabling VoiceOver, he reported the optional
  sign-in labels/message, Close, return to the daily card, and Settings focus all
  passed. This is owner-reported acceptance, not an independent speech capture.
- Ken also confirmed successful sign-in with VoiceOver enabled: "Signing in"
  was announced, the auth sheet closed to the daily card, and Settings replaced
  Sign In with Log Out and Delete Account. Credentials stayed on-device. This
  establishes the reported sign-in transition, not logout.
- Signed-in persistence passed by owner report: after force-closing and reopening
  the app with VoiceOver on, the daily card appeared without a login prompt and
  Settings still offered Log Out and Delete Account. This is a session check,
  not a measured cold-start performance result.
- The scoped physical iPhone account-transition and VoiceOver pass is complete
  by owner report. Preserve the individual results below and earlier historical
  QA; this does not establish all-device or final-distributed-candidate acceptance.
- Logout to guest passed by owner report with VoiceOver on: the daily card stayed
  visible without a login form, focus returned to Settings, and Sign In replaced
  Log Out and Delete Account.
- Guest persistence passed by owner report with VoiceOver on: force-closing and
  reopening returned directly to the daily card without an auth prompt, and
  Settings offered Sign In with no Log Out or Delete Account. This establishes
  guest-session behavior, not measured cold-launch performance or post-deletion
  persistence.
- Backend-error accessibility passed by owner report: one intentionally failed
  sign-in announced and focused the error, left the optional auth sheet open,
  and kept Close available. No repeated failed attempts or credentials were
  requested or captured. Successful sign-in retry after an error is a separate check.
- Reset accessibility passed by owner report in the optional auth sheet after
  the failed-sign-in check: "Sending reset link" and Check Your Email were
  announced, and OK returned focus to Forgot password. This confirms the reported
  request/confirmation flow, not email delivery or a completed password change;
  neither opening the email nor changing the password was requested.
- Reduce Motion passed by owner report with VoiceOver on: after enabling Reduce
  Motion, sign-in with the correct password succeeded, decorative sparkles/glow
  stayed static, and logout retained the daily card with focus on Settings. Ken
  reported no problematic large sliding/zooming transitions. This also establishes
  successful sign-in following the prior failed-sign-in/reset checks. Restoration
  of the temporary Reduce Motion setting was confirmed in the subsequent
  account-creation check.
- Account creation passed by owner report with VoiceOver on: Ken confirmed
  creating a new disposable account, hearing "Creating account," automatic sheet
  dismissal to the daily card, and signed-in Log Out/Delete Account menu options.
  He also confirmed restoring Reduce Motion to off. Credentials stayed on-device;
  no account deletion had been authorized or performed at that checkpoint.
- Deletion confirmation/cancellation passed by owner report with VoiceOver on:
  the warning/buttons were clearly announced, cancelling confirmation left the
  deletion form open, and cancelling the form returned to the card with Settings
  focus and signed-in Log Out/Delete Account options. The disposable account was
  left signed in; that cancellation check did not authorize permanent deletion.
- Ken subsequently confirmed that he is still signed into the disposable test
  account and explicitly approved permanently deleting only that account for the
  lifecycle check. Credentials and the destructive action stayed on-device under
  Ken's control.
- Permanent deletion passed by owner report: Ken confirmed "Deleting account"
  was announced, the deletion sheet closed to the daily card, focus returned to
  Settings, and Sign In replaced Log Out/Delete Account. Firebase Console state and rejection of the
  deleted account's credentials were not independently inspected in this pass.
- Post-deletion persistence passed by owner report with VoiceOver on: force-
  closing and reopening returned to the daily card without an auth prompt, and
  Settings offered Sign In with no Log Out/Delete Account. This closes the scoped
  iPhone lifecycle pass, not the separate performance or final-build checks.
- Reduce Motion was restored to off; VoiceOver remains on at the end of testing
  unless Ken chooses to restore its original off setting. No restoration of
  VoiceOver has yet been confirmed.

## Evidence and References

- [Main-based RC branching and promotion strategy](branching-strategy.md)
- [Physical accessibility and interaction QA](accessibility-interaction-qa.md)
- [Performance evidence and gaps](performance-qa.md)
- [Distribution evidence](distribution-readiness.md)
- [Listing and App Store Connect records](app-store-listing.md)
- [Credential history and release configuration](release-readiness.md)
- [Account/privacy audit](account-privacy-readiness.md)
- [Apple account-sign-in guidance](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)
- [Firebase session management](https://firebase.google.com/docs/auth/admin/manage-sessions)
- [Apple manual release](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option)
