# Testing and Acceptance

Use [app README](../DailyWhiskers/README.md#tests) for test commands and
[release checklist](release-checklist.md) for V1 acceptance decisions. This guide
is a repeatable protocol plus scoped evidence, not a second backlog or release gate.
Development tests do not retroactively validate the frozen V1 binary.

## V1.1 Build 3 Acceptance

Scope: accepted `1.1 (3)`, source
`f5413459e9b215a42816662e634ed8df3e7a53ad`, with artifact identity in
[distribution provenance](distribution-readiness.md#v11-candidate-provenance).
Ken's acceptance was reconfirmed through the release coordinator October 12, 2026.
This documentation-only update ran no new app tests, builds or physical checks.

- Scoped accessibility/layout acceptance is complete by owner report, with a
  screenshot-reviewed, owner-accepted nonblocking Close-control overlap.
  Do not convert that exception into a passed no-overlap assertion, weaken the
  existing layout tests, or infer blanket accessibility certification.
- Apple Passwords Fill (#85) and popup-dismissal manual-password loss (#86) remain
  open accepted risks deferred to V1.2. Single-password containment is not proof
  of a provider fix. Preserve the separate retest protocol below.
- Dedicated reviewer sign-in and logout to guest were owner-confirmed October 12
  at 22:02–22:03 UTC. No credentials were collected by this documentation task.
  Do not infer account-deletion, reset-delivery or every provider outcome from
  this successful sign-in.
- The supplied acceptance summary does not identify a complete per-check device,
  OS, text-size and orientation matrix. Those details remain unspecified here;
  historical V1/development devices must not be attributed to build 3.
- Prior exact-RC CI passed 96 unit cases / 146 executions and five smoke cases,
  with zero failures/skips/expected failures, plus unsigned Release and CI Gate.
  This is retained automated evidence, separate from owner-reported acceptance.

The [release checklist](release-checklist.md#v11-build-3-release-preparation)
owns current gates and approval status. The procedures and historical development
evidence below remain useful without overriding this candidate's scoped decision.

## Automated Checks

- `DailyWhiskers` scheme: unit tests for auth request locking/errors/routing,
  deletion ordering, registration policy/state, content decode/integrity/fallbacks,
  deterministic selection/rollover and packaged privacy/distribution configuration.
- `DailyWhiskersInteraction` scheme: opt-in offline simulator auth flows using
  `DEBUG`, `CI_SMOKE_TESTING` and the asserted offline launch marker. Use a
  dedicated simulator and an on-screen software keyboard. An offscreen keyboard
  accessibility tree does not satisfy the tappable-key precondition.
- Interaction checks cover guest dismissal/relaunch, keyboard/landscape reachability,
  repeated validation, Sign In visibility/editing/lifecycle, and registration
  navigation/credential isolation/visibility, the registration password masking
  on background, and Close/swipe draft clearing.
  They do not prove VoiceOver speech, real authentication, or backend request counts.
- Unit CI uses the fake Firebase plist. No live credentials, account creation,
  reset delivery or backend policy changes belong in those tests.
- Required offline UI CI runs all five `RegressionSmokeTests` and all
  `SavedCardsTests`, including the complete Favorites lifecycle. Both classes
  are covered by the zero-failure, zero-skip and zero-expected-failure gate.
- Native-field tests repeat registration mounts, detached-field clearing and
  synthetic native replacements across email/password focus changes, intentional
  select-all deletion and continued manual editing. These checks do not invoke
  a real strong-password provider. The offline UI regression repeats editing
  after Back, sheet Close and explicit process termination/relaunch. A valid
  single-password Done submission must reach only the rejecting offline boundary.
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
   Repeatedly open Sign In from Settings: focus must stay inside the presented
   sheet without bouncing back to Settings. Check Close and swipe dismissal return
   focus to Settings, then reopen and repeat through registration and a local
   missing-email reset error. Element-tree tests do not prove VoiceOver timing.
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
source, device, iOS version, and password manager used. Use the candidate that
contains the behavior under test; an older binary cannot validate a new control.
Use a controlled account for explicitly chosen live checks. Never put passwords,
reset links, or account addresses in the evidence. Automated tests use synthetic
input and injected operations; they do not prove live auth or password-manager use.

### Native Input Synchronization

Native-field unit coverage includes synthetic pending input in generic paired
fields and the current email/password form before editing callbacks, unrelated
SwiftUI refreshes, stable AutoFill traits, selection/end-editing callbacks, visibility with a pending edit, explicit
model clearing and view dismantling. Native edits must survive a refresh; explicit
model replacements and discarded forms must not be restored by queued work.
Programmatic secure-entry caret restoration must not publish a temporary cleared
model. Coverage also uses production-shaped `@State RegistrationForm` bindings
with native delegates active.
These tests exercise the bridge ordering, not an actual password provider.

Apple Passwords strong-password acceptance remains an unresolved physical-device
issue ([#85](https://github.com/KenWidemon/daily-whiskers/issues/85)). Keep its
provider results separate from manual registration, synthetic input tests and
association-file checks. The native synchronization and secure-refocus guard
protect independently reproduced input defects; they are not established fixes
for the provider failure. Temporary diagnostic/comparison screens are excluded
from the intended production candidate. Do not promote those experiment branches
as part of the ordinary authentication implementation.

Manual password loss after dismissing the strong-password popup with its corner X
is tracked separately in [#86](https://github.com/KenWidemon/daily-whiskers/issues/86).
Its real provider callback ordering and relationship to #85 remain unproven.
Synthetic native restoration and deliberate deletion checks do not establish
physical popup-cancellation behavior. Test that manual input survives dismissal
and repeated email/password focus changes without suppressing intentional clearing.
Both defects remain open; development integration does not establish release acceptance.

Registration's email account identifier uses `.username` content semantics with an
explicit `.emailAddress` keyboard, independently of the password field’s
`.newPassword` content semantics. This follows Apple's [field tagging guidance](https://developer.apple.com/documentation/security/enabling-password-autofill-on-a-text-input-view).
The keyboard must remain email-friendly when content semantics change.

Automatic strong-password support also depends on an [associated domain](https://developer.apple.com/documentation/security/about-the-password-autofill-workflow).
Verify the signed app/profile, the chosen credential domain's association file,
and actual device behavior before accepting this flow. Field tests alone do not
establish domain association or provider compatibility. Capability, provisioning,
and hosted-file changes require their own authorized configuration work.

For a provider-specific failure, record the provider and device separately. A
successful fill with another provider does not establish Apple Passwords acceptance.
Confirm generated input reaches the registration password field and remains editable
through focus/visibility changes, without submitting merely to test AutoFill.

### Single-Password Registration Retest

Use a newly identified candidate; the frozen two-field RC cannot validate this
change. Confirmation removal is containment of the cross-field trigger, not a
physical fix claim for #85 or #86. On iPhone and iPad, without submitting:

1. Dismiss Apple’s strong-password popup with Password empty, enter a synthetic
   password manually, then repeat Email → Password focus changes and popup dismissal.
   Confirm existing input survives and manual editing remains possible each time.
2. Separately exercise Apple Passwords Fill (#85), recording provider outcome
   independently of manual-entry and popup-dismissal outcomes.
3. Check Show/Hide, caret/range editing, select-all deletion to empty and re-entry.
   Background must mask; Back, Close and swipe dismissal must discard the draft.
4. Check VoiceOver privacy/order and reachable controls with the keyboard open at
   largest text, phone landscape and iPad portrait/landscape/narrow layouts.
5. Only with separate authorization, validate controlled account creation and
   email-reset recovery. Removing confirmation increases typo risk; optional
   visual review does not replace a nonvisual confirmation check.

### Shared Physical Session

Run on iPhone and iPad, in portrait and landscape where applicable. Mark each
row passed, failed, not run, or explicitly deferred; record who observed it.

| Check | DW-006 Sign In | DW-005 Create Account |
| --- | --- | --- |
| Entry and guest access | Settings opens optional Sign In with a masked, empty password. Close/swipe returns to the same daily card. | Create Account opens a separate form without a request; only email is prefilled. |
| Visibility and editing | Type, move the caret into the middle, select a range, toggle both ways, replace the selection, and keep typing. Value, selection, focus and keyboard stay intact. Dismiss the keyboard, refocus the masked password at a middle caret or selection, and type: the edit stays at that location. Toggle also works without focusing the field. | Repeat for the single registration password. |
| Privacy lifecycle | Reveal, switch apps/lock and return: masked with input retained. Close/swipe and reopen: masked with draft discarded. Going to registration and back also clears/masks the Sign In password. | Reveal, background and return: masked with input retained. Back or Close discards the registration password. |
| AutoFill | Fill an existing credential with the named manager. Reveal/hide and edit without losing it or unexpectedly offering a new password. | Generate/fill a compliant new password with the named manager; confirm it remains editable. Do not submit merely to test AutoFill. |
| VoiceOver controls/privacy | Fields and Show/Hide action and Hidden/Visible state are identified; focusing either masked or revealed password does not read its contents. Navigate away/back and edit; no focus trap. | Repeat for Password, Show/Hide and Back/Close; confirmation is absent. |
| Local validation | Existing six-character passwords remain eligible; invalid email/short input cannot sign in. Forgot password with empty/invalid email gives accessible feedback repeatedly. | Invalid email, minimum eight, ASCII uppercase/lowercase/digit each block submission with accessible feedback and error focus. |
| Largest accessibility text | With keyboard open, scroll to password, visibility control, reset and primary/navigation actions in portrait and landscape. Check clipping, overlap and 44-point targets. | Repeat for email/password, Show/Hide, submit and Back, including iPad narrow layouts. |
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

## Sharing Today's Card

Run `DailyCardShareTests` and `DailyCardShareVisualTests` in the unit scheme.
Coverage includes local midnight, immutable bytes/archetype across content replacement
and retry, all bundled artwork/quotes plus fallback, daily/saved pixel equality,
upright artwork pixel comparison, long-quote growth, PNG metadata, optional vibe/text
companion, render failures/retry, duplicate taps, preview metadata and cleanup.
Visual attachments cover the longest bundled quote and all six archetypes.
These checks do not establish physical share-sheet or VoiceOver acceptance.

For DW-017, run `DailyCardSharingTests/testActualExportPayloadsForTodayBonusAndSaved`
and `testLongestQuoteExportRetryCancelAndLargerText` in the offline interaction
scheme on iPhone and iPad. They capture paired app/system-sheet screenshots,
exercise Today/Bonus/Saved navigation, cancellation, injected render error/retry,
and sharing after scrolling at largest text. With the explicit CI-only
`--ci-smoke-export-evidence` flag, the exact image/text passed to the activity
controller is retained under the simulator app's Documents/ShareEvidence directory.
Inspect those actual payloads for full upright art, complete quote, Vibe, watermark,
dimensions and metadata; compare matched Today/Bonus/Saved versions byte-for-byte.
This opt-in evidence hook is compiled only with `DEBUG && CI_SMOKE_TESTING`;
ordinary Debug/Release exports remain memory-only. Keep raw output outside Git.
Watermark scale, opacity, placement and export sizing require Ken's visual approval.

The interaction suite checks launch in either orientation, repeated bidirectional
rotation before sharing, current-window canvas bounds and quote centering, scroll
recovery to the complete quote/vibe, and rotation with the system share sheet open.
The toolbar uses a view-only UIKit anchor: embedding a controller there previously
left the main canvas at its launch dimensions while the toolbar rotated.

On both iPhone and iPad, record the exact SHA/build and OS, then:

1. Before sharing, launch separately in portrait and landscape. Rotate in both
   directions repeatedly; verify the background fills the current window, the
   artwork stays centered, and scrolling reaches the complete quote and vibe.
   Return to the initial orientation and repeat after dismissing a share sheet.
   As a guest, enable airplane mode, open the daily card, and activate **Share
   Today's Card**. Inspect the preview for matching art, complete readable quote,
   optional vibe, branding, and absence of app/account chrome. The app's generation
   must work offline; destination delivery may require connectivity.
2. Dismiss without sending, then share again. Verify the daily card and Settings
   remain usable after Close or tapping outside the compact sheet/popover, the
   system sheet fits the device, and rotation does not break
   presentation. Do not send or post to others as part of automated validation.
   Inspect the system's Save Image/Save Photo action. With owner approval, choose
   it, let the owner handle any add-only Photos prompt, and inspect the saved
   artwork and complete quote. Verify cancellation or denial leaves sharing
   usable without a crash; do not change device privacy settings to force a pass.
   Record action availability separately from successful saving. Verify the built
   app contains `NSPhotoLibraryAddUsageDescription` and no read-access purpose.
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

## Saved Cards

Use the `CardRepositoryTests` unit suite and `SavedCardsTests` interaction class
with the same offline smoke compilation/launch gate documented in the app README.
Keep result bundles, screenshots and accessibility hierarchies privately; report
the exact source/diff, OS, simulator, selected checks and skips separately from CI.

- Save a displayed guest card, relaunch offline, browse newest-first, reopen and
  share it. Check the exact quote/vibe and full artwork; no account prompt appears.
- Check the text-free bookmark save control on Today and Bonus: outline when
  unsaved, filled when saved, with the same tint as Share and Settings. Its
  accessible action changes between **Save Card** and **Remove from Saved Cards**,
  and its **Saved/Not saved** value changes. The stacked-card collection navigation
  stays distinct. Save and unsave must preserve control and card geometry at
  standard and largest accessibility text sizes on regular and small phones.
- Save an identical version twice without changing order. Save another quote or
  artwork version of the same stable cat ID and verify both versions survive.
  Reordering/renaming the current pack must not change saved content identity.
- Replace current artwork, restart, and verify old bytes and actual old exports
  remain exact. Validate all current packaged original files against source hashes.
  Confirm the clean app bundle contains one `CardOriginals` folder and the catalog
  contains only AppIcon. Current and retained share PNGs must match exactly for
  identical content; exercise the default artwork loader in previews and fallback
  validation as well as the retained-byte display path. Record unsigned app file
  bytes separately from App Store download size, and simulator memory separately
  from physical-device acceptance.
- Inject a failure after row writes but before commit; prior favorites remain.
  Exercise interrupted transactions, corrupt/missing BLOBs, schema rejection,
  initial migration rollback/retry and consistent SQLite backup/restore including
  future day-selection references. Simulated disk-full errors are not a physical
  low-storage or power-loss test; record that limit.
- Unsave one card while leaving its open detail readable; its title must change
  from **Saved Card** to **Card**, then return on re-save. Confirm Clear is disabled
  while empty or busy, enabled after saving, and disabled again after removing the
  last card or confirmed clearing. Clear removes favorites only; cancel retains
  them and leaves Clear enabled. Referenced day content and active
  share content must survive cleanup. No implicit clear follows auth transitions.
- Compare Today and saved detail for the same card on the same device and text
  size. Verify matching themed frame, quote background, Vibe pill and text while
  retaining distinct navigation and Share/options controls. Compare actual card,
  quote and Vibe bounds as well as screenshots; shared code alone is not evidence
  of matching geometry. Open Saved Card Options, dismiss without removing, then
  remove and resave the open card; confirm the options control's accessible label,
  state and native activation, and a menu-action height of at least 44 points. Record
  the system toolbar trigger's bounds separately; do not assume its accessibility
  rectangle is 44 points high. No removal footer reserves content height. Use the
  saved snapshot's theme
  and content even when the current manifest differs.
- Review phone/tablet, default/largest text, portrait/landscape and Reduce Motion.
  Check empty and multi-card collections, centered tablet widths, and single-column
  accessibility layouts. At ordinary text sizes, all bundled cards must fit small
  iPhone portrait viewports with complete artwork and quote/vibe visible; preserve
  scrolling when larger text or unusually long content needs it. The secondary
  removal action retains its complete accessible label and a 44-point touch target.
  Saved thumbnails/quote excerpts must be usable and the reopened quote/vibe and
  actions reachable. VoiceOver speech/focus require separate observed acceptance;
  accessibility hierarchy and hittability assertions do not prove them.
- Check login, logout and account deletion with separately authorized accounts.
  The collection remains device-owned; deletion copy points to explicit clear.
  Review public privacy/support wording before release without treating source
  documentation changes as publication of those separate sites.

## Bonus Card

Run `BonusCardTests` in the unit scheme for local midnight, time-zone travel,
repeated dates, DST transitions, retained bytes across relaunch/backup, failed
commit rollback, corrupt content, exact Today exclusions and recent-seven fallback.
Corrupt a recent snapshot's metadata: its original date must stay unavailable while
future dates can select valid content and still avoid readable recent cards.
Run `DailyWhiskersUITests/BonusCardTests` with the offline smoke build/launch gate
for guest access, return to Today, reopening after relaunch, Favorites, existing
share-sheet cancellation and paired portrait previews. Keep original failures and
screenshots; do not classify a failure as intermittent without evidence.
The retained-bonus regression relaunches with `--ci-smoke-today-artwork-unavailable`
to fail Today's capture, then verifies reopening the original bonus, Save, Share
and return navigation. This injection requires both `DEBUG`/`CI_SMOKE_TESTING` and
`--ci-smoke`; it is absent from ordinary and Release builds.

Compare Today, Bonus and its saved detail on regular/small iPhone and iPad with
ordinary and largest text. Preserve complete ordinary-phone artwork/quote/Vibe,
quote padding, the monochrome bookmark Save control and unchanged share export.
At larger text and in landscape, scroll to both quote boundaries and Vibe; verify
menu, Save and Share remain reachable. Test foreground midnight and travel on an
explicitly authorized device without changing the owner's clock/settings as part
of automation. Current automation tests date policy separately from real clock
notifications. VoiceOver reading order, speech and focus restoration require
observed acceptance; hierarchy and hittability alone do not establish them.

A retained date must survive Favorites clearing, navigation and reopening with a
changed or missing content pack. A corrupt retained snapshot shows an error and
never consumes a second selection. No content match should produce a usable Today
and a retryable unavailable message. The known registration-focus risk and deferred
account checks elsewhere in this guide remain unchanged by bonus-card validation.
