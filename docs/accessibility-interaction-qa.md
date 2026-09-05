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

- Normally signed simulator build and all 32 regression tests passed.
- On a separate iPhone 17e simulator, keyboard Next moved input from email to
  password; Done with invalid credentials did not start an auth request.
- Software keyboard displayed the Hide Keyboard control, which dismissed it.
- Accessibility tree exposed the heading, fields, and buttons in visual order,
  with disabled auth actions correctly represented. Decorations were absent.
- Login displayed dark status-bar content against its light background.
- Source audit confirmed the static motion branches and minimum target dimensions.

## Remaining Manual Acceptance Checks

- VoiceOver speech: loading announcements, error focus, complete reading order,
  and alert dismissal focus on a physical device.
- Toggle Reduce Motion on/off while each screen remains alive; confirm glow and
  sparkles stop/resume without relaunch. Also check screen transitions.
- Valid keyboard Done submission with a controlled account and repeated presses.
- Software-keyboard scrolling in landscape and with large Dynamic Type; iPad
  multitasking and rotation checks carried forward from 4A.
- Logout failure alert navigation with an injected storage failure.

The remaining live checks were limited by simulator focus changing during QA.
Accessibility-tree inspection is not a substitute for listening with VoiceOver.
Performance profiling remains Step 5.
