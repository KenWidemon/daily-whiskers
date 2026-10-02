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
  repeated validation, and registration navigation/credential isolation/visibility.
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

## Sharing Today's Card

For DW-002, run `DailyCardShareTests` in the unit scheme. Coverage includes a
snapshot across local midnight, all bundled artwork/quotes plus fallback, text
measurement and pixel bounds, optional vibe/text companion, PNG metadata,
render failures/retry, duplicate taps, and completion/cancellation cleanup.
These checks do not establish physical share-sheet or VoiceOver acceptance.

On both iPhone and iPad, record the exact SHA/build and OS, then:

1. As a guest, enable airplane mode, open the daily card, and activate **Share
   Today's Card**. Inspect the preview for matching art, complete readable quote,
   optional vibe, branding, and absence of app/account chrome. The app's generation
   must work offline; destination delivery may require connectivity.
2. Dismiss without sending, then share again. Verify the daily card and Settings
   remain usable, the system sheet fits the device, and rotation does not break
   presentation. Do not send or post to others as part of automated validation.
3. With VoiceOver and largest accessibility text, verify the action's name/hint,
   progress feedback, system-sheet navigation, text companion, and return focus
   after cancellation. Repeat from an already signed-in session without creating
   an account merely to share.
4. Exercise failure/retry using the injected renderer test seam; confirm retry
   uses the captured card. Review the longest supported quote's exported image
   at natural size. Automated measurement is evidence against clipping, not a
   substitute for visual legibility review.

Keep account/regression prerequisites and artwork/quote redistribution approval
explicit in the linked issue/PR. No physical check or rights approval is implied
by passing unit tests or opening a draft PR.
