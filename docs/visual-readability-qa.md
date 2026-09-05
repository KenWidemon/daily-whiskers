# Step 4A: Visual Readability

## Changes

- Centered, scrolling login content with a 520-point maximum width; the available
  viewport follows keyboard safe-area changes.
- Multiline headings and button labels, padded fields, and expandable card text.
- Daily content scrolls in compact layouts and at accessibility text sizes.
  Only the cosmic background ignores safe areas; controls/content respect them.
- Login retains its light palette and the daily screen requests dark appearance,
  including system chrome. This is an intentional per-screen appearance choice.
- Dark text on amber buttons, darker placeholders/secondary labels, and a
  content-sized dark quote background improve readability across image themes.
- Disabled auth buttons use reduced saturation rather than faded text.

## Verification

An isolated UIKit hosting harness rendered the real SwiftUI views with bundled
content and fake Firebase configuration. No live login was required. Inspected
top and bottom snapshots where content scrolls.

| Layout | Size (points) | Text size | Result |
| --- | --- | --- | --- |
| Small phone | 375 x 667 | Large (default) | Login and quote readable |
| Pro Max | 440 x 956 | Large | Centered layout; bounded card |
| Phone landscape | 667 x 375 | Large | Bottom controls/quote reachable by scrolling |
| iPad-sized | 820 x 1180 | Large | Content width capped |
| Small phone | 375 x 667 | Accessibility 5 | Labels wrap; quote/vibe and auth controls reachable by scrolling |

Reviewed one card for each of the six archetypes, plus the longest bundled quote.
These are rendered viewport checks, not a claim of physical-device verification.

Calculated color-pair contrast for the specified colors: primary button text
against the darker amber endpoint is 6.88:1; secondary text against lavender is
5.98:1; placeholder gray against lavender is 5.49:1. Composited appearance still
needs device review, especially with display accessibility settings enabled.

All 32 regression tests passed after the layout changes. The temporary visual
capture harness also completed successfully and was not added to the app target
or the committed unit-test suite.

After restarting Simulator, the normally signed review build launched with the
existing session intact. A live Pro Max screenshot confirmed white status-bar
content on the dark daily screen and visible settings, quote, and vibe.

## Manual Checks Still Needed

- Confirm software-keyboard scrolling on a device, especially landscape.
- Confirm dark status-bar content on login, including transitions from the daily screen.
- Check actual device rotation, iPad multitasking, and light/dark system settings.
- VoiceOver, focus/submission behavior, touch-target audit, and live Reduce Motion
  changes belong to Step 4B.

The interactive simulator initially timed out; live keyboard checks are not
marked passed. Earlier login/daily screenshots provide the before baseline; new
renders are available in `/tmp/whiskers-4a-captures` locally and the live daily
screen is captured at `/tmp/whiskers-4a-live.png`.
