# Testing and Acceptance

Use [app README](../DailyWhiskers/README.md#tests) for test commands and
[release checklist](release-checklist.md) for V1 acceptance decisions. This guide
is a repeatable protocol plus scoped evidence, not a second backlog or release gate.
Development tests do not retroactively validate the frozen V1 binary.

## Automated Checks

- `DailyWhiskers` scheme: unit tests for auth request locking/errors/routing,
  deletion ordering, registration policy/state, content decode/integrity/fallbacks,
  deterministic selection/rollover and packaged privacy/distribution configuration.
- `DailyWhiskersInteraction` scheme: opt-in signed-out simulator flows. Use a
  dedicated simulator and an on-screen software keyboard. An offscreen keyboard
  accessibility tree does not satisfy the tappable-key precondition.
- Interaction checks cover guest dismissal/relaunch, keyboard/landscape reachability,
  repeated validation, Sign In visibility/editing/lifecycle, and registration
  navigation/credential isolation/visibility.
  They do not prove VoiceOver speech, real authentication, or backend request counts.
- Unit CI uses the fake Firebase plist. No live credentials, account creation,
  reset delivery or backend policy changes belong in those tests.
- Keep the known largest-text Sign In landscape assertion and keyboard precondition
  intact. A skipped/deferred test is not a pass; report exact selected tests/results.

## Physical Acceptance Protocol

Record source/build, installation provenance, model, exact OS, date, text size,
Reduce Motion, power conditions and signed-in state. Distinguish observed from
owner-reported results. Use the exact distributed candidate for release acceptance.

1. Launch into guest access. Check card/quote/vibe, Settings, and public links.
   Same-day background/foreground should preserve the card. Account UI is optional.
2. Check Sign In, Create Account, reset, Close/Back and credential clearing against
   the tested version's design. Use a controlled account; credentials stay on-device.
3. Verify successful login, session persistence, logout to guest, retries and
   duplicate-request protection. A neutral reset alert does not prove email delivery;
   changing a password requires completing the email link yourself.
4. With VoiceOver, check reading order, actionable labels, initial/repeated local
   and backend errors, loading announcements, reset dismissal to Forgot password,
   Settings focus after dismissal/logout, and no decorative sparkle announcements.
5. With explicit approval for a disposable account, test deletion cancellation,
   reauthentication, Delete Permanently, return to guest and guest relaunch.
   Never delete the reviewer account. A generic login error alone is not backend proof.
6. Check all account forms and the daily card at default/largest text, both phone
   landscapes, keyboard-open scrolling, and iPad portrait/landscape/narrow/side-by-side
   layouts. Full controls must be reachable; don't substitute keyboard-hidden checks.
7. Toggle Reduce Motion live: decorations become static and auth transitions avoid
   large motion; disabling it resumes animation. Restore changed device settings.
8. For natural rollover, background before local midnight and foreground afterward
   without force-quit, restart, update or clock change. Compare the expected local-date
   card. A new-process launch demonstrates startup selection, not in-process rollover.

## Account Form Acceptance

Combined DW-005/DW-006 procedure, with each issue's criteria kept separate.
Update when account-form behavior or agreed acceptance criteria change; record
individual runs in the linked issues, not a new repository session log.

### Identify the Build

Record source commit (and any uncommitted changes), app version/build, installation
source, device, iOS version, and password manager used. Build the DW-006 task branch
for this round; an older DW-005 binary cannot validate the new Sign In control.
Use a controlled account for explicitly chosen live checks. Never put passwords,
reset links, or account addresses in the evidence. Automated tests use synthetic
input and injected operations; they do not prove live auth or password-manager use.

### Shared Physical Session

Run on iPhone and iPad, in portrait and landscape where applicable. Mark each
row passed, failed, not run, or explicitly deferred; record who observed it.

| Check | DW-006 Sign In | DW-005 Create Account |
| --- | --- | --- |
| Entry and guest access | Settings opens optional Sign In with a masked, empty password. Close/swipe returns to the same daily card. | Create Account opens a separate form without a request; only email is prefilled. |
| Visibility and editing | Type, move the caret into the middle, select a range, toggle both ways, replace the selection, and keep typing. Value, selection, focus and keyboard stay intact. Dismiss the keyboard, refocus the masked password at a middle caret or selection, and type: the edit stays at that location. Toggle also works without focusing the field. | Repeat for password and confirmation independently. |
| Privacy lifecycle | Reveal, switch apps/lock and return: masked with input retained. Close/swipe and reopen: masked with draft discarded. Going to registration and back also clears/masks the Sign In password. | Reveal both, background and return: masked. Back or Close discards both registration passwords. |
| AutoFill | Fill an existing credential with the named manager. Reveal/hide and edit without losing it or unexpectedly offering a new password. | Generate/fill a compliant new password and confirmation with the named manager; confirm both remain editable. Do not submit merely to test AutoFill. |
| VoiceOver controls/privacy | Fields and Show/Hide action and Hidden/Visible state are identified; focusing either masked or revealed password does not read its contents. Navigate away/back and edit; no focus trap. | Repeat for both password controls and Back/Close. |
| Local validation | Existing six-character passwords remain eligible; invalid email/short input cannot sign in. Forgot password with empty/invalid email gives accessible feedback repeatedly. | Invalid email, minimum eight, ASCII uppercase/lowercase/digit and exact confirmation each block submission with accessible feedback and error focus. |
| Largest accessibility text | With keyboard open, scroll to password, visibility control, reset and primary/navigation actions in portrait and landscape. Check clipping, overlap and 44-point targets. | Repeat for all three fields, both visibility controls, submit and Back. |
| Pending request and failure | With an owner-controlled request, verify progress speech, disabled duplicate actions/dismissal, accessible backend/network failure and retry. | Repeat registration request checks; creating a real account is a separate deliberate test action. |
| Success and recovery | Controlled successful sign-in returns to the same daily card. Verify reset behavior only with deliberate authorization to send an email. | Controlled registration success follows the existing session route to the daily card. |

A layout/element-tree assertion does not establish VoiceOver speech or real
password-manager behavior. A successful request does not prove reset delivery.
Do not infer a pass for an unexercised row from confidence in the implementation.

Keep both issues open until their agreed criteria are accepted or explicitly waived
and applicable merges are complete. This procedure does not authorize backend
policy changes, live account mutation, merge or release.

## Visual and Performance Guardrails

- Content uses scrolling, bounded widths, dynamic text, and content-sized quote
  backgrounds. Inspect all six themes and long quotes; do not rely on color-pair
  contrast calculations alone for composited readability.
- Decorative images/sparkles are hidden from accessibility; curated image descriptions
  are not implemented. Do not publish broad accessibility labels from scoped checks.
- Timelines request a minimum 1/30-second interval and pause while inactive;
  Reduce Motion uses static decoration. Requested cadence is not achieved FPS.
- Profile optimized builds on a physical device with bounded, app-scoped captures.
  Record motion/power/thermal conditions and compare like-for-like runs. A saved
  trace without a visibly launched app is not a successful startup measurement.
- Stop and reassess failed Instruments attachment/launch paths rather than repeating
  them to force closure. Do not restore the removed profiling harness, fill device
  memory, change clocks, or add caches without a justified separately approved plan.
- Persistent allocation, cumulative allocation, RSS and peak memory are different
  measures. UIKit caching alone does not establish a leak or justify cache replacement.

## V1 Deferrals and Performance Evidence

Ken explicitly approved post-V1 diagnosis of the largest-text phone landscape
simulator failure, detailed natural-startup/hitch profiling, memory pressure,
battery/long-session and lower-memory-device behavior. These remain unverified
risks, not passes; exact-TestFlight owner acceptance is in checklist #1/#7.

Retained evidence that motivates later investigation:

- September 10, pre-guest source `37f9e00`, iPhone 17 Pro Max / iOS 26.6.1:
  two 30-second card captures recorded three and one 16.67 ms hitches respectively.
  Attribution and user-visible severity were not established; no FPS guarantee.
- September 11 isolated 31-image/two-pass harness, source `37f9e00` plus driver
  `0371d04`, iPhone 17 Pro Max / iOS 26.6.2: 250.91 MiB persistent heap plus
  anonymous VM, including 226.12 MiB IOSurface. The later graph was broadly flat,
  but markers were incomplete. This is not RSS/peak, leak-freedom, memory-pressure,
  foreground rollover, or provider-init timing evidence. Harness was removed.
- The later paused-launch/attach/resume trace had owner-visible launch but a dyld
  timeline warning. It is not a natural cold-start benchmark. Auth/foreground
  graphs did not establish per-cycle ownership or absence of leaks.
- September 13/14 local Release from `cc7eff5a0b61ea2a9b33fb579f647520e7d8ebe5`,
  iPhone 17 Pro Max / iOS 26.6.2: qualitative launches/foreground/card behavior and
  natural overnight rollover passed by owner report, supported by process continuity.
  Instruments attachment failed; no replacement numerical performance claim.

The old Step 4A/4B/5 journals, raw-path references and full measurement tables are
recoverable through [documentation history](README.md#historical-recovery).

## DW-005 Development Evidence

This section preserves consequential acceptance gaps while detailed run journals
move out of README. Scope: [DW-005 issue #54](https://github.com/KenWidemon/daily-whiskers/issues/54),
[merged PR #69](https://github.com/KenWidemon/daily-whiskers/pull/69), not frozen V1.
Record future progress in the issue rather than extending this session log.

- September 28, after eight-character-policy revision: 68 unit tests in nine suites
  passed on iPhone 17 / iOS 27.0; two focused iPad Air 11-inch (M4) / iOS 26.5
  checks passed for registration validation/visibility/background masking and
  largest-text scrolling. These are historical results, not a run of this cleanup.
- Before the policy revision, eight iPad interaction checks passed. Three iPhone
  17 Pro / iOS 26.5 keyboard tests failed their offscreen-keyboard precondition;
  a separate iPhone 17 / iOS 27.0 run passed four targeted keyboard/registration
  checks. Do not report the earlier full phone run as green.
- Ken reported physical iPhone 17 Pro Max / iOS 27 checks on source `a7b37a3`:
  dedicated form/navigation, password continuation after reveal/hide, background
  masking, guided AutoFill round, scoped VoiceOver labels/error focus/privacy,
  and largest-text portrait/landscape reachability. Installed binary was not
  independently verified; individual password-manager behavior was not supplied.
- Physical iPad and live-request VoiceOver progress/backend-error checks remained
  unverified at the recorded checkpoint. Merge does not establish those results.
  Registration passes do not close the deferred Sign In landscape scenario.
- Ken deferred Firebase policy alignment. Recorded September 28 backend policy
  was minimum 6 / maximum 4096, no required character classes, enforcement ENFORCE.
  The app's new-account form requires minimum 8 plus uppercase/lowercase ASCII and
  a number. Do not claim server enforcement or silently change Firebase; preserve
  existing-account login/reset compatibility. Recheck live state before any change.

## DW-006 Development Evidence

Scope: [DW-006 issue #55](https://github.com/KenWidemon/daily-whiskers/issues/55)
and [PR #70](https://github.com/KenWidemon/daily-whiskers/pull/70), not frozen V1.
The [combined DW-005/DW-006 acceptance procedure](#account-form-acceptance)
retains separate issue criteria, physical build provenance and scoped results.
Record subsequent progress in the issues; the following is a September 28 snapshot.

- Source `a860af90a32d52ef10cd10b9279c266ab31c0cd2`, Xcode 27.0 / Debug:
  72 unit tests in ten suites passed on iPhone 17 / iOS 27.0. Native-field tests
  cover exact Unicode/whitespace, selection, focus, continued editing, AutoFill
  traits, accessibility-value privacy and non-submission.
- All ten interaction tests passed on iPhone 17 / iOS 27.0 and iPad Air 11-inch
  (M4) / iOS 26.5, including registration regressions and the unchanged Sign In
  largest-text landscape assertion. These are scoped device results, not a rerun
  of the historical Pro Max scenario or physical acceptance.
- The strengthened nonempty-password dismissal test passed on both destinations.
  Its combined run had an iPad runner-launch failure before execution; the isolated
  iPad rerun passed. App code was unchanged after the full suite runs.
- Physical setup was agent-verified: signed Debug 1.0 (1) from the same source,
  built with Xcode 27.0, installed and launched on iPhone 17 Pro Max and iPad Pro
  13-inch (M4), both OS 27.0 (24A437). No debug test-account credentials were supplied.
- Ken reported passes on both devices for password value/selection/focus/keyboard
  preservation across Show/Hide and editing; independent registration controls;
  background masking with values retained; Sign In Close/reopen clearing; email-only
  registration prefill and password clearing when navigating back and reopening.
- Exercised local validation passed: registration email, minimum length, each
  required character class and confirmation mismatch; Sign In five/six-character
  eligibility and repeated invalid-email reset feedback. Apple Passwords filling,
  registration strong-password suggestion, automatic confirmation and editing
  after filling also passed on both devices. These are owner-reported results.
- Current-build VoiceOver, largest-text physical layout, live-request progress/error,
  successful authentication/reset delivery, device locking, swipe dismissal,
  unfocused visibility toggling and registration Close dismissal remain unverified.
  Firebase alignment remains deferred. No live account mutation or backend-policy
  change occurred in these rounds. Documentation merges do not retest installed
  binaries, resolve the historical Pro Max simulator result or waive pending criteria.

Physical artifact SHA-256 values: executable
`8b2bacb88b6e745872fba7e43fc1d38a3fbe1d497c41bcd97c83056e5d4e48a3`;
Debug library `9a820e7e7474ae78651c00176207f71a01a05ad818b65dc8afb87dc965df32db`.
Detailed rounds and historical local artifact references remain in
[DW-006 issue #55](https://github.com/KenWidemon/daily-whiskers/issues/55);
those local references are not durable release evidence. Historical rounds are also in Git at
`825fe1909e87167b6dfa0cffc33262cb35e17eab:docs/dw005-dw006-acceptance.md`.
