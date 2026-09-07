# Step 4B: Accessibility and Interaction

## Behavior

- Email Next moves focus to Password. Password Done submits sign-in only when
  validation passes and the shared auth request lock is free.
- A keyboard toolbar provides Hide Keyboard. Starting an auth request dismisses
  field focus; interactive scroll dismissal remains available.
- The login title is a heading. Error text is an accessibility focus target and
  is scrolled into view when presented. Loading operations post an announcement.
- Native reset/logout alerts provide their own announcement and navigation;
  reset dismissal restores accessibility focus to the reset button, and logout
  cancellation restores focus to Settings.
- Settings and the debug test-account button now have explicit 44-point targets.
  Existing auth buttons are at least 54 points high and reset is at least 44.
- Glow, sparkles, and quotation-mark decorations are hidden from accessibility.
  Backgrounds do not intercept touches. Quotes and vibe tags retain their labels.
- Cat illustrations remain decorative: the manifest has no descriptive alt text.
  Adding curated image descriptions would require a separate content change.
- Reduce Motion replaces the login glow's timeline with a static gradient.
  Both sparkle layers already select static canvases from the same environment
  setting. Auth screen transitions now also honor Reduce Motion.

## Verified

- Normally signed simulator build and all 35 regression tests passed.
- The concurrency matrix covers all five auth operations, including logout,
  as both the in-flight request and the blocked subsequent request.
- Regression tests cover every operation's announcement text, successful sign-in
  feedback cleanup, and dismissal of error/reset feedback. Existing injected
  keychain-error coverage verifies logout failure and successful retry.
- On a separate iPhone 17e simulator, keyboard Next moved input from email to
  password; Done with invalid credentials did not start an auth request.
- Software keyboard displayed the Hide Keyboard control, which dismissed it.
- Accessibility tree exposed the heading, fields, and buttons in visual order,
  with disabled auth actions correctly represented. Decorations were absent.
- Login displayed dark status-bar content against its light background.
- Source audit confirmed the static motion branches and minimum target dimensions.
- Live login Reduce Motion toggle passed on iPhone 17e: with the setting enabled,
  screenshots taken two seconds apart were byte-identical. Disabling the setting
  resumed visible sparkle/glow changes in the same app process, without relaunch.
  Reduce Motion was restored to its original disabled setting afterward.

## Repeatable UI Checks

The opt-in `DailyWhiskersInteraction` scheme runs three XCTest UI checks on a
dedicated signed-out simulator:

- Portrait: Email Next moves to Password Done; empty Done stays on login with
  Sign In and Create Account disabled.
- Landscape: start with an on-screen password keyboard and scroll until the
  complete Create Account button is within the visible viewport.
- Repeat landscape scrolling with the largest accessibility text-size launch
  override. Interactive scrolling may dismiss the keyboard, as designed.

Each keyboard precondition checks a tappable key contained within the app window.
Merely finding a keyboard accessibility element is insufficient: the first iPad
runs exposed keyboard elements below the screen. Showing the software keyboard
resolved that setup issue; all three checks then passed on iPad Air 11-inch (M4),
iOS 26.5. These tests never submit valid credentials or sign out a user. Existing
unit-test CI remains separate. See the README for invocation and setup.

Latest run of the final UI-test code: all three checks passed on iPad Air 11-inch
(M4), and the existing 35 unit tests passed. On iPhone 17 Pro Max, portrait
navigation and normal-size landscape scrolling passed, but largest-text landscape
scrolling still failed. After eight upper-form drags, the captured Create Account
frame was y=378 through y=465.3 in a 440-point-high window. The test correctly
rejects this as not fully visible. Whether this is an app interaction defect or
simulator gesture/rotation behavior remains unresolved; do not mark phone
largest-text scrolling accepted or ship this test branch as fully green.

Failure screenshots and UI trees are attached to the `.xcresult` bundle. The
phone diagnostic run is locally available in `/tmp/whiskers-ui-phone-verified.log`;
the passing iPad and unit runs are `/tmp/whiskers-ui-ipad-final.log` and
`/tmp/whiskers-unit-final.log`. No application code changed during this test pass.

## Remaining Manual Acceptance Checks

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

- VoiceOver speech: loading announcements, error focus, complete reading order,
  and alert dismissal focus on a physical device.
- Check auth screen transitions with Reduce Motion on a physical device.
- Live repeated keyboard submission while a request is in flight. A single valid
  Done submission passed; the request-lock unit tests cover duplicate blocking.
- Physical-device full-form scrolling, iPad multitasking/window resizing, and
  signed-in rotation. The simulator login scrolling checks are described above;
  they do not cover those other configurations.
- Resolve the phone largest-text landscape UI-test failure before accepting that
  configuration. Keep the failing assertion; do not substitute a keyboard-hidden
  check for the current keyboard-open-start scenario.
- Logout failure alert navigation and accessibility focus with an injected storage
  failure. State-level failure/retry tests pass, but do not verify alert focus.

The earlier simulator text-injection limitation was avoided by having the user
enter credentials. Simulator login scrolling now has repeatable coverage;
multitasking, signed-in interaction, and physical-device checks remain open.
The simulator's Accessibility settings do not expose iOS VoiceOver, so speech and
focus acceptance need a physical device.
Accessibility-tree inspection is not a substitute for listening with VoiceOver.
Performance profiling remains Step 5.
