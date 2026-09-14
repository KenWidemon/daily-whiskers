# Step 4B: Accessibility and Interaction

> **Evidence log, not the release roadmap.** Step 4B is a historical development
> label. As of September 13, scoped pre-guest iPhone/iPad checks and guest-first
> iPhone account-transition/VoiceOver checks passed by owner report. Final-candidate
> repeats remain under [release checklist](release-checklist.md) #1 and #7.
> Earlier failures/pending statements apply to their recorded candidate; later
> results supersede them only for the tested scope. The largest-text landscape
> simulator failure is unresolved and explicitly deferred for V1. See the
> [documentation map](README.md) for evidence and temporary-file conventions.

## Behavior

- Email Next moves focus to Password. Password Done submits sign-in only when
  validation passes and the shared auth request lock is free.
- The extra Hide Keyboard toolbar action was removed at Ken's request on
  September 13. Starting an auth request dismisses field focus; interactive scroll
  dismissal remains available, and Close dismisses optional auth.
- The login title is a heading. Error text is an accessibility focus target and
  is scrolled into view when presented. Accepted login/reset operations post an
  announcement before starting backend work, independent of view redraw timing.
- Native reset/logout alerts provide their own announcement and navigation;
  reset dismissal schedules accessibility focus back to the reset button after
  the native transition settles (passed on the physical phone by owner report).
  Logout cancellation requests focus back to Settings; an isolated physical iPad
  check passed by owner report, as recorded below. Final-candidate repeats remain.
- Settings and the debug test-account button now have explicit 44-point targets.
  Existing auth buttons are at least 54 points high and reset is at least 44.
- Glow, sparkles, and quotation-mark decorations are hidden from accessibility.
  Backgrounds do not intercept touches. Quotes and vibe tags retain their labels.
- Cat illustrations remain decorative: the manifest has no descriptive alt text.
  Adding curated image descriptions would require a separate content change.
- Reduce Motion replaces the login glow's timeline with a static gradient.
  Both sparkle layers already select static canvases from the same environment
  setting. Auth screen transitions now also honor Reduce Motion.

## Historical Initial Verification

The 35-test/five-operation results below predate account deletion and guest-first
access. PR #41 recorded 56 tests in eight suites; see the release checklist for
subsequent regression evidence. Do not treat these older counts as the current suite.

- Normally signed simulator build and all 35 regression tests passed.
- The concurrency matrix covers all five auth operations, including logout,
  as both the in-flight request and the blocked subsequent request.
- Regression tests cover every operation's announcement text, successful sign-in
  feedback cleanup, and dismissal of error/reset feedback. Existing injected
  keychain-error coverage verifies logout failure and successful retry.
- On a separate iPhone 17e simulator, keyboard Next moved input from email to
  password; Done with invalid credentials did not start an auth request.
- Historical check: the software keyboard displayed the Hide Keyboard control,
  which dismissed it. That control was removed September 13 by product request.
- Accessibility tree exposed the heading, fields, and buttons in visual order,
  with disabled auth actions correctly represented. Decorations were absent.
- Login displayed dark status-bar content against its light background.
- Source audit confirmed the static motion branches and minimum target dimensions.
- Live login Reduce Motion toggle passed on iPhone 17e: with the setting enabled,
  screenshots taken two seconds apart were byte-identical. Disabling the setting
  resumed visible sparkle/glow changes in the same app process, without relaunch.
  Reduce Motion was restored to its original disabled setting afterward.

## Repeatable UI Checks

The opt-in `DailyWhiskersInteraction` scheme defines five XCTest UI checks on a
dedicated signed-out simulator; it opens optional auth through Settings:

- Guest entry, Close/reopen, discarded form state, and guest relaunch persistence.
- Portrait: Email Next moves to Password Done; empty Done stays on login with
  Sign In and Create Account disabled.
- Landscape: start with an on-screen password keyboard and scroll until the
  complete Create Account button is within the visible viewport.
- Repeat landscape scrolling with the largest accessibility text-size launch
  override. Interactive scrolling may dismiss the keyboard, as designed.
- Repeat empty-email reset validation in portrait and check full error visibility.
  This does not establish VoiceOver speech or focus.

Each keyboard precondition checks a tappable key contained within the app window.
Merely finding a keyboard accessibility element is insufficient: the first iPad
runs exposed keyboard elements below the screen. Showing the software keyboard
resolved that setup issue; all three checks then passed on iPad Air 11-inch (M4),
iOS 26.5. These tests never submit valid credentials or sign out a user. Existing
unit-test CI remains separate. See the README for invocation and setup.

Historical pre-guest UI-test run: all three then-existing checks passed on iPad Air 11-inch
(M4), and the existing 35 unit tests passed. On iPhone 17 Pro Max, portrait
navigation and normal-size landscape scrolling passed, but largest-text landscape
scrolling still failed. After eight upper-form drags, the captured Create Account
frame was y=378 through y=465.3 in a 440-point-high window. The test correctly
rejects this as not fully visible. Whether this is an app interaction defect or
simulator gesture/rotation behavior remains unresolved; do not mark phone
largest-text simulator scrolling accepted or describe the full suite as green.
The later physical pass and explicit V1 deferral below supersede the release-blocker
interpretation, not the failing assertion. Four focused guest-first checks later
passed on iPhone 17e; the deferred fifth check was not rerun.

Failure screenshots and UI trees are attached to the `.xcresult` bundle. The
phone diagnostic run is locally available in `/tmp/whiskers-ui-phone-verified.log`;
the passing iPad and unit runs are `/tmp/whiskers-ui-ipad-final.log` and
`/tmp/whiskers-unit-final.log`. No application code changed during this test pass.

## September 7 Follow-up

Retested the merged PR #32 baseline on the dedicated, signed-out iPhone 17 Pro
Max (iOS 26.5). After restarting the simulator and displaying its software
keyboard, the original suite again passed portrait navigation and default-size
landscape scrolling, but failed largest-text landscape scrolling. The failure
remains reproducible; restarting alone is not a fix.

Diagnostic experiments did not establish a fix:

- Moving the drag beside the text fields still failed.
- Launching in portrait, then rotating and waiting for landscape window bounds,
  still failed.
- A standard `swipeUp()` with the software-keyboard precondition satisfied also
  failed the full-button visibility assertion.
- One intermediate run failed the keyboard precondition instead. That run is
  not evidence about scrolling.

The simulator also produced cropped/misoriented failure screenshots and initially
incomplete accessibility output. Direct simulator gestures did not establish
successful scrolling either, but these environment symptoms prevent attributing
the result conclusively to app layout. All experimental test changes were
discarded; the original keyboard and visibility assertions remain unchanged.
No production app code changed and no credentials were submitted.

Local evidence: `/tmp/whiskers-phone-sept7-fresh.log` (original full suite),
`/tmp/whiskers-phone-sept7-margin.log`,
`/tmp/whiskers-phone-sept7-rotation.log`, and
`/tmp/whiskers-phone-sept7-clean-swipe.log`. The baseline screenshot and hierarchy
were exported to `/tmp/whiskers-sept7-baseline-attachments`.

Final regression checks against the unchanged test code: all three iPad Air
11-inch (M4), iOS 26.5 UI tests passed, followed by all 35 unit tests in four
suites. Logs: `/tmp/whiskers-ipad-sept7.log` and
`/tmp/whiskers-unit-sept7.log`. The phone suite remains two passes and one failure.

Historical next diagnostic (physical comparison since completed below): compare
the same keyboard-open, largest-text landscape flow on
a physical phone or a separate simulator runtime before choosing an app fix or
a test-harness adjustment. Do not weaken the acceptance assertion to get green.

## Physical Phone Follow-up (September 13, 2026)

Ken performed the manual comparison on the connected iPhone 17 Pro Max, starting
from the login screen. The requested setup was the largest accessibility text
size, landscape orientation, and the password field's software keyboard open.
Ken reported that the entire Create Account button could be brought into view
by scrolling and that the keyboard stayed visible while scrolling. No credential
entry or account creation was requested.

This is an owner-reported pass for physical-phone full-button reachability in
that scenario, not an independently captured screenshot or automated result.
The installed build identity and OS version were not reverified during this
manual check; repeat against the final distributed candidate for release sign-off.

The earlier simulator failure remains unresolved. The physical result does not
establish its root cause or make the simulator suite green. Keep the original
keyboard-open precondition and full-button visibility assertion unchanged.
No app or test code was changed based on this result. Further diagnosis should
compare simulator gestures, rotation, viewport, and text-size configuration with
the passing manual flow before choosing an app fix or test-harness adjustment.

Release exception approved by Ken on September 13: skip further diagnosis of
this simulator failure for V1. The former step 2 (_physical device scrolling_,
not current release checklist #2)
is complete with this explicit exception and the owner-reported physical-phone
pass, not a resolved defect or green simulator suite. Preserve the test and its
assertions; do not disable it
or convert the failure to a pass. Track simulator diagnosis as post-release work.
This exception does not waive final-candidate physical checks or broader QA.

Restore the original text-size and rotation-lock settings after testing;
restoration has not yet been confirmed. Broader physical-device accessibility,
signed-in interaction, and performance acceptance remain separate checks.

## Physical VoiceOver Follow-up (September 13, 2026)

On the connected iPhone 17 Pro Max login screen, Ken reported that VoiceOver
reads all content in a sensible order, clearly identifies every field and
button, and does not announce decorative sparkles. This passes the login
reading-order, field/button labeling, and decorative-sparkle exclusion checks
by owner report. No automated speech capture or independent focus recording
was taken, and the installed build identity was not reverified for this check.

Local validation failed by owner report: activating Forgot password with an
empty email displayed "Enter a valid email address." but did not move VoiceOver
focus or read the message. This path does not send a reset email or make a
Firebase request. The failure is separate from the deferred simulator scrolling
issue and was not waived. The candidate retest below passed by owner report.

Candidate fix: replace the error label's immediate `onAppear` focus request and
separate scrolling callback with a cancellable task on the rendered error. It
yields for insertion, scrolls the error into view, waits 350 milliseconds for
scrolling/keyboard dismissal to settle, then requests accessibility focus. Each
non-nil error assignment has a fresh presentation ID so repeated identical errors
also trigger the task. Clearing the error or removing the view cancels pending
work; stale presentation IDs cannot refocus an older error. The timing is a
bounded workaround, not proof of the root cause.

New state tests cover repeated validation/backend presentation IDs and clearing
feedback without generating a new presentation. All 48 unit tests in seven
suites passed on iPhone 17e, iOS 26.5, with a successful simulator build.
Evidence: `/tmp/whiskers-voiceover-20260913-tests.xcresult` and matching `.log`.
The focused repeated local-error visibility UI check also passed on iPhone 17e,
iOS 26.5 (one test, zero failures); evidence is
`/tmp/whiskers-voiceover-20260913-ui.xcresult` and matching `.log`. This is not a
VoiceOver speech/focus result or a rerun of the deferred landscape check.
Ken confirmed "It works!" after deployment when asked to verify automatic focus
and spoken error feedback. Record the empty-email validation focus/speech retest
as passed by owner report. Ken subsequently confirmed that repeat activation
also works, passing repeated identical-error focus and speech on the same phone.
Ken then confirmed that the live reset request's loading announcement and
Check Your Email alert work, but dismissing OK restores focus to Password rather
than Forgot password. Record reset loading/alert presentation as passed and reset
dismissal focus as failed on the first candidate by owner report; the second
candidate retest below passed. No password change was requested.
At this checkpoint, other operations' loading announcements, backend-error focus,
and signed-in reading order were still open; subsequent results are recorded below.

Before candidate deployment, CoreDevice reported the physical iPhone 17 Pro Max
on iOS 26.6.2 with Daily Whiskers version 1.0 (1). These version strings alone do
not establish which source revision produced the previously installed binary.

The candidate built successfully in Release configuration with development
signing and was installed over the existing phone app without uninstalling it.
CoreDevice reported successful launch, followed by Ken's successful physical
VoiceOver retest. Device build log:
`/tmp/whiskers-voiceover-20260913-device-build.log`. Local source/binary hashes are
recorded in `/tmp/whiskers-voiceover-20260913-source-hashes.txt` and
`/tmp/whiskers-voiceover-20260913-binary-hash.txt`. Version/build remain 1.0 (1).
The test simulator is shut down. No App Store upload or submission occurred.

Reset-dismissal candidate: the dismissal handler now ignores duplicate callbacks,
clears accessibility focus, and starts a cancellable task. After a 350-millisecond
native-alert settling interval it scrolls the reset button into view, yields for
layout, and requests focus there. Editing, a new reset/auth action, or leaving the
view cancels pending restoration; confirmation/error/request checks reject stale
work. This is a bounded timing workaround, not proof of the native-focus race.
All 48 unit tests in seven suites passed again for this candidate; evidence is
`/tmp/whiskers-reset-focus-20260913-tests.xcresult` and matching `.log`.
The focused repeated-error visibility UI check passed (one test, zero failures),
and the signed Release device build passed. CoreDevice reported installation
over the existing app and successful launch of the second candidate. Ken then
confirmed that dismissing OK returns VoiceOver focus to Forgot password rather
than Password. Reset-dismissal focus passes by owner report on this candidate.
This does not establish other alerts' dismissal behavior. Evidence uses the prefix
`/tmp/whiskers-reset-focus-20260913-`: `ui.xcresult`, `ui.log`, `device-build.log`,
`source-hashes.txt`, and `binary-hash.txt`. The test simulator is shut down.

On the second candidate, Ken reported that signed-in daily-card VoiceOver reading
works: the quote, vibe tag, and Settings are clearly identified without decorative
callouts. Record that scoped daily-screen reading check as passed by owner report.
Ken clarified that the "Signing in" announcement was completely silent, not
partially spoken or incorrect. This failed on the second candidate, separately
from the successful reset announcement; the third-candidate retest below passed.

Announcement candidate: `AuthRequestState` accepts an injected announcement
callback and invokes it synchronously after taking the request lock but before
backend work. `AuthView` supplies the VoiceOver callback instead of observing
operation changes for speech. Short loading announcements use high priority to
avoid interruption once started. Authentication is not delayed, and blocked
duplicates or invalid-email reset validation do not emit loading announcements.
Other callers retain their existing behavior through a no-op default callback.
New regression cases cover callback order for immediately completed operations,
blocked duplicates, invalid reset, and separate accepted retries. All 51 unit
tests in seven suites passed on iPhone 17e, iOS 26.5; evidence is
`/tmp/whiskers-announcement-20260913-tests.xcresult` and matching `.log`.
The focused repeated-error visibility UI test and signed Release device build
also passed. CoreDevice reported installation over the existing app and successful
launch of the third candidate. Ken confirmed "All good now!" after the requested
VoiceOver sign-out/sign-in retest, passing sign-in speech by owner report.
Evidence uses `/tmp/whiskers-announcement-20260913-`: `ui.xcresult`, `ui.log`,
`device-build.log`, `source-hashes.txt`, and `binary-hash.txt`. The test simulator
is shut down. Ken then confirmed "LGTM!" for the requested reset regression check
on this build: loading announcement and confirmation alert are spoken, and OK
returns focus to Forgot password. Record these as passed by owner report after
the shared announcement-delivery change. No App Store upload or submission occurred.

## Physical Reduce Motion Follow-up (September 13, 2026)

On the third candidate installed on the iPhone 17 Pro Max, Ken confirmed the
requested Reduce Motion exercise with "Again, LGTM!": decorative glow/sparkle
motion stops on login and the daily card when Reduce Motion is enabled, the
sign-in transition has no sliding or scaling, and decorative animation resumes
after disabling the setting. Record these as passed by owner report, not a new
frame-by-frame capture or performance measurement. Restoration of the owner's
preferred setting was requested but not separately confirmed.

## Physical Rotation Follow-up (September 13, 2026)

Ken confirmed the signed-in rotation exercise on the current iPhone candidate:
portrait to landscape left, landscape right, and back to portrait. Quote/vibe
readability, scrolling where needed, and Settings menu access in landscape passed
by owner report, with no reported clipped text, overlapping controls, stuck
scrolling, or unexpected card changes. This does not cover iPad window resizing
or multitasking. Restoration of the preferred rotation-lock setting was not
separately confirmed.

## Physical Keyboard Submission Follow-up (September 13, 2026)

Ken reported "Nothing to note!" after the requested valid-credential keyboard
submission exercise: tap Password Done twice quickly, stopping if the keyboard
dismisses. Record no reported duplicate alerts, errors, repeated transitions, or
unstable daily-card outcome on the current iPhone candidate. Whether a second
activation reached the handler before keyboard dismissal was not independently
observed. This is a visible-interaction pass, not a measurement of Firebase
request counts; the concurrency unit tests establish in-flight duplicate blocking.
Credentials stayed on-device and no repeated attempt was requested.

## Physical iPad Setup (September 13, 2026)

CoreDevice detected the connected iPad (`iPad16,6`) on iPadOS 26.6.1. Auth source
hashes still match the tested third phone candidate. The iPad-targeted Release
build initially timed out waiting for the destination because Developer Mode was disabled;
a direct CoreDevice app query independently returned error 10005 for the same
reason. That attempt did not install or launch the candidate or perform layout
checks, and no device security settings were changed by the agent.
Build log: `/tmp/whiskers-ipad-acceptance-20260913-build.log`.

After Ken enabled Developer Mode and confirmed readiness, CoreDevice app queries
succeeded. The next build failed because the development profile did not include
the iPad. Xcode then successfully built Release with automatic provisioning/device
registration enabled. CoreDevice reported successful installation and launch of
Daily Whiskers, followed by Ken's login layout acceptance below. No app
source changed during setup, no credentials were entered by the agent, and no
App Store upload occurred. Follow-up evidence uses
`/tmp/whiskers-ipad-acceptance-20260913-`: `build-retry.log`,
`build-provisioning.log`, `source-hashes.txt`, and `binary-hash.txt`.

Ken confirmed "LGTM" for the signed-out iPad login exercise: full-screen portrait
and landscape, software password keyboard, narrow-window resizing, and another
app alongside Daily Whiskers. Fields/buttons remained reachable by scrolling
without reported clipped text, overlap, or keyboard obstruction. Record these
as passed by owner report at the device's current text size, not acceptance of
all Dynamic Type sizes.

Ken then reported "No issues whatsoever" for the signed-in iPad exercise:
portrait, landscape, narrow-window and side-by-side layouts; quote/vibe
readability, scrolling where needed, Settings access, and switching to the
neighboring app and back without a card change. Record these as passed by owner
report at the current text size. This is not a real-day rollover test or proof
of every multitasking configuration.

## Isolated Logout-error Check (September 13, 2026)

Ken approved a temporary QA-only build for logout-error speech, Cancel focus,
and Try Again recovery. It is generated outside the repository with a separate
bundle ID (`com.example.kenwidemon.dailywhiskers.logoutqa`) and display name
Whiskers Logout QA. Eleven production Swift files are copied with hash checks;
only the entry point and router are replaced. The copied production logout view
and error mapping remain unchanged. Firebase is not configured, no service plist
is bundled, and the isolated sources contain no `Auth.auth()` calls. Live auth,
password reset, and account deletion actions are disabled in the stub router.

The first two simulated logout attempts throw a Firebase-shaped Keychain error;
the third changes only in-memory QA state and displays QA Logout Complete.
The intended sequence is failure -> Cancel, failure -> Try Again -> simulated
success. This checks the production error UI, not real Keychain failure/recovery.
The normal Daily Whiskers app and its session remain untouched. No harness files
or flags were added to the shipping project. The signed Release QA build passed,
and CoreDevice reported successful installation and launch on the iPad.
Ken confirmed that Cancel returns VoiceOver focus to Settings after the first
simulated failure. Record that focus check as passed by owner report on iPad.
Ken then confirmed VoiceOver reads the title/message on the second failure and
Try Again reaches QA Logout Complete. Record alert speech, Cancel focus return,
and simulated retry recovery as passed by owner report. No logout-view production
fix was needed. This does not verify a real Keychain failure or backend recovery.

Cleanup completed: CoreDevice confirmed QA app uninstall and launch of normal
Daily Whiskers. The temporary generated project, derived data, preparation script,
and path pointer were removed. The normal app was not uninstalled or replaced.
Retained local evidence: `/tmp/whiskers-logout-qa-20260913-build-retry.log` and
`/tmp/whiskers-logout-qa-20260913-source-hashes.json`. No runnable QA harness remains
in the workspace or temporary project location. Apple development provisioning
records created for the separate QA bundle were not removed.

## Historical Follow-ups and Final-Candidate Repeat Scope

This section preserves earlier runs and scenario coverage, not a second release
checklist. Use canonical #1/#7 for final-candidate acceptance and #2 for performance.

September 5-6 follow-up: signed-in Reduce Motion passed on iPhone 17e. Static
screenshots were byte-identical two seconds apart; disabling the setting restored
visible sparkle changes in the same app process. The original setting was restored.

September 6 keyboard follow-up: with credentials entered by the user on iPhone
17e, activating the software keyboard's Done button signed in successfully and
displayed the expected daily card. No credentials were changed or recorded.

September 6 landscape follow-up on a separate, signed-out iPhone 17 Pro Max:
the focused password field remained visible with the software keyboard at normal
text size. Changing live to the largest accessibility size moved the field behind
the keyboard. AuthView now scrolls the focused field into view after a Dynamic
Type change. Repeating the same landscape test showed the enlarged password field
above the keyboard. Text size was restored to its original `large` value. This
targeted check does not establish full-form scrolling or iPad acceptance.

The focused-field fix built successfully and all 35 existing regression tests
passed on the separate Pro Max simulator. These are auth/content tests; the
Dynamic Type positioning result above was verified visually, not by those tests.

Fresh iPad Air 11-inch (M4), iOS 26.5 follow-up: login remained centered and
width-constrained in portrait and landscape. In landscape, the focused password
field stayed above the software keyboard at normal text size and after a live
change to the largest accessibility size with the fix installed. Text size was
restored to `large`. The first app launch stalled after first-boot migration;
one simulator restart recovered it. These checks cover the full-screen login,
not iPad window resizing/multitasking or signed-in card interaction.

- Repeat the tested VoiceOver flows on the final candidate. Signed-in reading,
  sign-in/reset/create/delete announcements, alert focus, and guest transitions
  have scoped owner-reported passes in the September 13 records. Login reading
  order, field/button labels, decorative-sparkle exclusion, initial
  and repeated local-validation error focus/speech, reset loading/confirmation,
  and reset-dismissal focus passed by owner report on September 13. Backend-error
  announcement/focus also passed in the guest-first follow-up below. Repeat against
  the final distributed candidate.
- Physical Reduce Motion passed by owner report on September 13 for login/card
  decorative motion, the sign-in transition, and animation resuming when disabled.
  Repeat against the final distributed candidate. Sign-out with Reduce Motion
  additionally passed in the guest-first follow-up below.
- The rapid keyboard-submission exercise passed by owner report on September 13
  with no visible issues. Actual delivery of a second activation was not verified;
  the request-lock unit tests cover in-flight duplicate blocking. Repeat the
  visible-interaction check on the final distributed candidate.
- Repeat physical full-form scrolling, rotation, and iPad resizing/multitasking
  on the final distributed candidate. Signed-in iPhone rotation and landscape
  Settings access, plus signed-out and signed-in iPad window/side-by-side checks,
  passed by owner report on September 13 at the tested text sizes. The earlier
  iPhone Create Account reachability check did not establish candidate identity.
- Post-release follow-up: diagnose the phone largest-text landscape simulator
  UI-test failure, explicitly deferred for V1 by Ken on September 13. Keep the
  failing assertion; do not substitute a keyboard-hidden check for the current
  keyboard-open-start scenario.
- Logout failure alert speech, Cancel focus return, and simulated Try Again
  recovery passed by owner report using unchanged production UI in an isolated
  iPad QA app on September 13. State-level failure/retry tests also pass. This
  does not establish real Keychain failure/recovery or all-device acceptance.

The earlier simulator text-injection limitation was avoided by having the user
enter credentials. Simulator login scrolling has repeatable coverage with the
explicitly deferred phone failure. The September 13 physical results above cover
the tested phone/tablet configurations; remaining gaps and final-candidate repeats
are listed here rather than treating all physical acceptance as complete.
The simulator's Accessibility settings do not expose iOS VoiceOver, so speech and
focus acceptance need a physical device.
Accessibility-tree inspection is not a substitute for listening with VoiceOver.
Performance profiling is tracked under current release checklist #2; the
performance document's Step 5 title is historical development numbering.

## September 13 Guest-First Follow-Up

Ken confirmed Dani's approval of optional sign-in and account tools. The daily
card is now the root for guests and signed-in users, including while Firebase
restores its session. Settings presents optional authentication in a sheet;
signed-in users retain logout and password-confirmed deletion. Successful auth
and session-ending transitions dismiss obsolete account sheets without replacing
the daily card. A different signed-in identity also invalidates an open deletion
form. No Firebase anonymous account is created.

The auth Close button and interactive sheet dismissal are disabled while an auth
request is running. Closing auth discards unfinished form state. Settings focus
is requested after sheet dismissal or sign-out, not on initial guest-session
restoration. Deletion and logout have separate request/feedback state. Ken also
requested removal of the extra Hide Keyboard toolbar button; keyboard submission
and interactive scroll dismissal remain.

Testing notes:

- Five new unit tests cover guest/loading/signed-in account access, auth dismissal,
  session loss, and invalidating deletion for a changed identity.
- The UI scheme now enters auth through Settings. A new test verifies the guest
  card, absence of guest logout/deletion, Close, discarded form state, and guest
  relaunch. Keyboard navigation asserts Hide Keyboard is absent.
- Initial keyboard checks could not find an onscreen software keyboard. Ken
  authorized temporarily disconnecting the simulator's hardware keyboard. This
  was a test setup issue, not a passing keyboard check.
- Default-text landscape then exposed an ambiguous test selector: the daily card
  remains behind auth and both contain scroll views. The test now targets
  `auth-form`, preserving the keyboard-open-start scenario, visibility assertion,
  and swipe budget. The targeted landscape rerun passed.
- The largest-accessibility-text landscape test remains explicitly deferred for
  V1 and was not rerun or weakened. Shared entry/scroll targeting reflects the new
  modal hierarchy; its reachability assertion is unchanged.
- The scoped physical iPhone pass is now complete by owner report, as recorded
  below. No live account was created, signed in, reset, or deleted by these
  automated checks. Physical account operations were performed by Ken. Earlier
  physical results remain historical evidence; final-candidate repeats still apply.

Final regression evidence is recorded in [the release checklist](release-checklist.md).

### Physical Guest Entry and Close

The tested signed Release app was installed over the existing app on iPhone 17
Pro Max without uninstalling or clearing session data. Signature validation and
the device launch command succeeded. Ken confirmed the app was signed out and
VoiceOver was initially disabled. After being asked to enable VoiceOver, open
Settings > Sign In, inspect Close/field/account labels and the optional-sign-in
message, then activate Close without entering credentials, Ken reported
"Everything LGTM." Record this as owner-reported passage of that bounded flow:
the daily card remains available and VoiceOver focus returns to Settings.
No independent speech recording or successful authenticated transition is
established by this result. Binary provenance:
`/tmp/whiskers-guest-physical-binary-hash.txt`.

### Physical Successful Sign-In

With VoiceOver enabled on the same iPhone build, Ken confirmed that signing in
with his active test account announced "Signing in," dismissed the auth sheet
automatically to the daily card, and replaced Sign In in Settings with Log Out
and Delete Account. Credentials remained on-device. This is owner-reported
acceptance of the successful sign-in transition and signed-in menu, not an
independent speech capture, relaunch/persistence check, or logout check.

### Physical Signed-In Persistence

Ken subsequently confirmed that force-closing and reopening the same iPhone app
with VoiceOver enabled returned to the daily card without a login prompt, with
Log Out and Delete Account still available in Settings. Record signed-in session
persistence as passed by owner report. No launch timing was measured, and this
does not close the separate performance acceptance item.

### Physical Logout to Guest

Ken confirmed all four requested logout behaviors with VoiceOver enabled on the
same iPhone build: Settings > Log Out left the daily card visible without opening
auth, VoiceOver focus returned to Settings, and the menu replaced Log Out/Delete
Account with Sign In. Record the successful logout transition as passed by owner
report. Guest relaunch persistence and Reduce Motion were not established by
this check; no independent speech capture or backend/session inspection occurred.

### Physical Guest Persistence

After the successful logout check, Ken confirmed that force-closing and reopening
the same iPhone app with VoiceOver on returned directly to the daily card without
a login prompt. Settings still offered Sign In and did not offer Log Out or
Delete Account. Record guest persistence as passed by owner report. No launch
timing was measured, and this does not establish post-deletion persistence or
complete the separate performance acceptance item.

### Physical Failed-Sign-In Accessibility

With VoiceOver on in the optional auth sheet, Ken was asked to submit his active
test account's email with an intentionally incorrect password once. He reported
"LGTM" for the error being announced and receiving VoiceOver focus, the sheet
remaining open, and Close remaining available. Record this bounded backend-error
accessibility check as passed by owner report. Credentials stayed on-device;
there was no independent speech capture or repeated failed-login test. Successful
recovery/retry after an error is not established by this result.

### Physical Reset in Optional Auth

Following the failed-sign-in check, Ken confirmed all requested reset behaviors
with VoiceOver on: activating Forgot password once announced "Sending reset link,"
the Check Your Email alert was announced, and activating OK returned focus to
Forgot password. Record these optional-sheet announcement/confirmation/focus
behaviors as passed by owner report. The test did not ask him to open the email
or change his password. The neutral confirmation is not proof of email delivery,
and successful sign-in retry remains a separate check. No credentials or reset
link were retrieved or stored by the agent.

### Physical Reduce Motion and Successful Retry

Ken was asked to keep VoiceOver on, enable Reduce Motion, sign in with the correct
password, and then log out. He reported "LGTM" for both successful actions, static
decorative sparkles/glow, and logout retaining the daily card with VoiceOver focus
on Settings. No problematic large sliding/zooming transitions were reported.
Record these bounded motion/transition checks as passed by owner report on the
same iPhone build. Successful sign-in followed the earlier failed-sign-in/reset
checks. This does not measure animation performance or establish all-device
acceptance. Restoration of Reduce Motion was confirmed in the next check below.

### Physical Account Creation

Ken was asked to restore Reduce Motion to off, keep VoiceOver on, and create a
new disposable account using an unused email he controls and a unique password.
He confirmed that "Creating account" was announced, the optional auth sheet
closed to the daily card, and Settings offered Log Out and Delete Account.
Record account creation/announcement/dismissal and restoration of Reduce Motion
as passed by owner report. Credentials remained on-device and were not retrieved
or recorded by the agent. The new account was left signed in; this confirmation
does not authorize permanent deletion.

### Physical Deletion Cancellation

With VoiceOver on and the disposable account signed in, Ken confirmed that the
deletion confirmation warning and buttons were clearly announced. Cancelling
the confirmation left the deletion form open; cancelling that form returned to
the daily card with focus on Settings and Log Out/Delete Account still available.
Record this bounded warning/cancellation/focus check as passed by owner report.
He was explicitly instructed not to choose Delete Permanently. No irreversible
deletion was authorized by this check, and no credentials were retrieved by the
agent.

### Guest-First Deletion Approval

After the cancellation check, Ken explicitly confirmed that he is still signed
into the disposable test account and approved permanently deleting that account
for the final lifecycle check, after being told deletion cannot be undone.
This approval is limited to that disposable account. The owner performs the
destructive action on-device; no credentials are requested by the agent. Approval
alone did not establish execution; the result is recorded below.

### Physical Permanent Deletion to Guest

After explicit approval, Ken was asked to keep VoiceOver on, delete only the
disposable account using its on-device password, and choose Delete Permanently.
He reported "Confirmed" for hearing "Deleting account," the sheet closing to the
daily card, VoiceOver focus returning to Settings, and Sign In replacing Log Out
and Delete Account. Record this bounded deletion/announcement/guest-return flow
as passed by owner report. The subsequent relaunch result is recorded below.
The agent did not independently inspect Firebase Console, test rejected deleted-
account credentials, capture speech, or perform the destructive action itself.

### Physical Post-Deletion Persistence and Pass Closure

Ken confirmed that force-closing and reopening the same iPhone app with VoiceOver
on returned directly to the daily card without a login prompt. Settings offered
Sign In, with no Log Out or Delete Account. Record post-deletion guest persistence
as passed by owner report. This completes the scoped physical iPhone account-
transition and VoiceOver pass, not all-device acceptance, independent Firebase
account-absence verification, measured performance, or final-build retesting.

Production/test source hashes still match the tested revision. Only QA/checklist
documentation changed during physical acceptance. Reduce Motion was restored to
off by owner confirmation; VoiceOver was initially off and remains on unless the
owner restores it. No VoiceOver restoration has yet been reported. No commit,
push, PR, App Store metadata update, upload, submission, or release was performed
as part of these physical checks.
