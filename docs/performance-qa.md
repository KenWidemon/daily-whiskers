# Step 5: Performance Tuning

## Changes

- Login glow and both sparkle layers request a minimum interval of 1/30 second,
  rather than unrestricted display-rate updates. SwiftUI may schedule more slowly;
  this is a ceiling request, not a guaranteed frame rate.
- All three timelines explicitly pause whenever their scene is not active.
- Reduce Motion continues to remove the timelines and render static decoration.
- Artwork, particle counts, motion speeds, gradients, shadows, and layout are
  unchanged. Animation time still uses wall-clock time, so returning to the app
  resumes at the current phase rather than replaying missed frames.

## Measurements

September 5, 2026; Xcode 26.6, iOS 26.5, iPhone 17e simulator, normally signed
Debug builds. Before revision: `81f1e72`. After: this branch's working tree.
The screen was idle and signed out with the keyboard hidden and motion enabled.
Ten `ps` observations at one-second intervals were collected after launch settled.

| Login | Before | After |
| --- | --- | --- |
| Process CPU range | 10.4-13.6% | 6.4-8.9% |
| Resident memory | About 340 MiB | About 340 MiB |

A three-second pre-change `sample` captured SwiftUI timeline updates and login
glow rendering. After foregrounding Settings and waiting ten seconds, five
one-second observations reported 0.0% app CPU. Returning to the app retained its
process ID. This confirms observed quiescence, not that the explicit pause alone
caused it: iOS also suspends background apps.

These short Debug-simulator samples are directional, not a controlled benchmark,
GPU measurement, leak diagnosis, energy estimate, or frame-rate guarantee. Another
simulator was booted during the session; host load was not controlled. Do not turn
the CPU difference into a shipping performance or battery-life claim.

## Image and State Audit

- The catalog contains 31 portrait PNGs at 1024x1536 (approximately 6 MiB each
  if decoded as four-byte RGBA), plus app-icon sizes. Catalog source size is 85 MiB;
  this is not the installed or App Store download size.
- The daily card displays one named asset. Manifest integrity validation resolves
  all referenced images with `UIImage(named:)`; UIKit may cache those images.
  No eager custom decoding or extra image cache was introduced. Allocations and
  memory-pressure testing are needed before changing this path.
- Sparkle/glow timeline updates remain isolated to decorative subviews, not the
  auth form or daily-content selection logic.
- Foreground content refresh already skips selection when the day is unchanged.
  Manifest loading occurs in provider initialization, not inside a timeline.
  The eager default `DailyContentState()` initializer can still load a provider
  during parent reconstruction; measure this with SwiftUI Instruments before
  introducing shared caching or changing state ownership.

## Repeatable Acceptance Pass

1. Use the same device, build configuration, motion setting, and visible screen
   for both revisions. Wait for startup work to settle. Do not run tests or other
   simulator builds during sampling.
2. Obtain the app PID from `xcrun simctl launch DEVICE_ID
   com.example.kenwidemon.dailywhiskers`. Sample with `ps -p PID -o %cpu=,rss=` at
   one-second intervals. RSS is reported in KiB. Keep raw observations and ranges.
3. In Instruments, capture CPU Profiler, Animation Hitches, and Allocations for
   idle login, a signed-in card, scrolling, rotation, and repeated foregrounding.
4. Toggle Reduce Motion live on both screens. Confirm static decoration; disable
   it and confirm smooth resumption. Background and foreground without relaunch.
5. Measure memory across daily-card changes and repeated sign-in/sign-out cycles;
   distinguish UIKit caching from retained view/controller growth.
6. Repeat in an optimized build on a physical device, including a high-refresh
   display and a lower-memory device. Inspect visual smoothness before accepting
   the 30 Hz cadence. Preserve the current design unless profiling justifies more.

## Remaining

The signed simulator build and all 35 existing regression tests passed after the
changes. These tests cover auth/content behavior, not measured frame pacing.

- Both available simulators were signed out during this pass. The second device's
  screenshot confirmed login, so its measurements are not a daily-card baseline.
  Signed-in CPU/GPU, image allocations, rollover memory, and auth-cycle profiling
  remain unverified. No user credentials or auth bypass were added for profiling.
- Physical-device smoothness, frame pacing, energy use, and live reduced-motion
  acceptance remain required. Existing accessibility acceptance items are tracked
  separately in `accessibility-interaction-qa.md`.
- No shadow/compositing or image-format changes were made without evidence.
