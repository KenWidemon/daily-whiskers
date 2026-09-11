# Step 5: Performance Tuning

## Focused Device Pass (September 10-11, 2026)

Current checkpoint: `codex/device-performance`, based on merged revision
`37f9e00`. Login/card sampling, foreground/auth-cycle allocations, and the card's
Reduce Motion comparison are recorded below. A September 11 evening startup
attempt saved a trace but failed owner-visible launch confirmation; it is not a
valid startup baseline. The owner approved a separate image-profiling harness;
its bounded two-pass exercise completed with the limitations recorded below.
This task adds evidence and the isolated harness only. No shipping-app code has
changed. No recording is
active at this checkpoint. A later paused-launch/attach/resume capture obtained
owner-visible initialization-memory evidence, with a dyld timeline warning.
Natural cold-launch timing and real foreground/day-transition memory behavior
remain unestablished; neither is proved by the isolated exercise.

Raw traces are in `/tmp` and may not survive system cleanup. Results and limits
are recorded here; no automatic continuation is scheduled. No simulator was
started for the September 11 evening work.

The owner chose to proceed with performance before the broader physical-device
acceptance checklist. That checklist, including the known largest-text landscape
scrolling failure, remains pending; it is not waived or marked complete.

- Baseline: merged `codex/develop` revision `37f9e00`; task branch
  `codex/device-performance`.
- Development-signed Release build succeeded with locked package versions.
  Log: `/tmp/whiskers-device-performance-build.log`.
- No app code, authentication bypass, caching, or animation changes have been
  introduced for this pass.
- The iPhone was subsequently connected, and the optimized app was installed and
  launched successfully. The iPad remains unavailable.
- Installed Instruments templates include CPU Profiler, Animation Hitches,
  Allocations, App Launch, SwiftUI, and Power Profiler.

### Bounded Measurement Order

1. Install the optimized development build on the connected iPhone. Record OS,
   revision, Low Power Mode, Reduce Motion, thermal/power conditions, and whether
   the screen is signed in. Do not compare Debug-simulator numbers as a device
   before/after baseline.
2. Capture app launch and a 30-second settled idle login CPU trace. Capture a
   separate animation-hitch trace rather than stacking expensive instruments.
3. Have the owner sign in directly on-device with a working account. Do not use
   the previously deleted account, exposed shared credentials, or collect a
   password in chat/logs. Repeat settled idle CPU and animation measurements on
   the daily card.
4. Capture Allocations during five foreground/background cycles and up to three
   owner-operated sign-in/out cycles. Inspect persistent growth and allocation
   stacks; a high but stable UIKit image cache is not by itself a leak.
5. Compare motion enabled/disabled on the same screen and build, restoring the
   owner's original setting. Observe visual pacing; the requested 30 Hz timeline
   cadence is not proof of achieved frame rate or energy efficiency.
6. Inspect image/provider allocations. Record rollover allocation testing as
   pending unless an actual day transition or an explicitly scoped test harness
   is exercised; do not change the user's system clock or silently add one.
7. Make only trace-supported changes, then repeat the affected scenario under
   comparable conditions and run regression tests. If no issue is established,
   publish evidence without speculative optimizations.

Keep traces outside the repository, app-scoped where supported. Limit each
recording and stop/reassess if Instruments hangs rather than repeatedly burning
time on the same failed capture. This first-device pass does not establish
lower-memory-device, long-session, battery-life, or full V1 acceptance.

The sections below retain earlier simulator evidence and its limitations.

### First Physical Login Baseline

September 10, 2026, iPhone 17 Pro Max, iOS 26.6.1 (23G83), app PID 10991.
Owner confirmed the login screen with Reduce Motion and Low Power Mode both off.
The development-signed Release build uses merged app code at `37f9e00`.
Recordings were sequential and attached after launch, not launch-time tests.

- CPU Profiler completed its 30-second limit (31.39-second trace envelope), with
  1,651 CPU-profile sample rows. Device thermal state was Nominal throughout.
  The potential-hangs table contained no rows.
- Leaf-binary shares of recorded cycle weight included SwiftUICore 12.16%,
  CoreFoundation 11.62%, AttributeGraph 8.54%, QuartzCore 7.80%, and RenderBox
  7.71%. These are sample-weight shares, NOT app CPU utilization percentages.
  Some frames were unsymbolicated; no source-level bottleneck is established.
- A separate 30-second Animation Hitches capture completed. Its hitches table
  contained no rows; 1,121 frame-lifetime records spanned 30.60 seconds. Median
  and p95 adjacent frame-start gaps were approximately 33.34 ms. These aggregate
  records are not a display refresh-rate or sustained FPS guarantee.
- No performance optimization is justified by this short idle sample alone.
  Signed-in, interaction, memory/allocation, launch, and motion comparison captures
  remain pending. No leak, battery-life, or complete performance sign-off is made.
- Raw traces: `/tmp/whiskers-device-initial-cpu-20260910.trace` and
  `/tmp/whiskers-device-login-hitches-20260910.trace`.
- Exports: `/tmp/whiskers-device-login-cpu-samples.xml`,
  `/tmp/whiskers-device-login-cpu-health.xml`, and
  `/tmp/whiskers-device-login-frames.xml`. No traces or credentials are committed.

### Physical Signed-in Follow-up (September 10)

After owner-operated sign-in, the same process (10991) remained active on the
same device/build. Low Power Mode and Reduce Motion were unchanged from the
owner-confirmed off baseline. No authentication bypass was used.

- A 30-second CPU capture completed (31.06-second envelope): 1,308 sample rows,
  nominal thermal state, and no potential-hang rows. Leaf-cycle-weight shares
  included RenderBox 18.23%, AGXMetalG18P 16.82%, QuartzCore 11.65%, and SwiftUICore
  9.32%. These are not CPU-utilization or GPU-utilization percentages.
- First card Animation Hitches capture recorded three 16.67 ms hitches at about
  0.49, 26.06, and 29.86 seconds. The last two were annotated "Potentially
  expensive app update(s)." Its 1,004 frame-lifetime records had median/p95
  adjacent start gaps of 33.34 ms. This calls for confirmation, not speculative
  removal of shadows or a claim that a particular view caused the hitches.
- A second 30-second idle-card recording completed with one 16.67 ms hitch
  (about 15.50 seconds) and nominal thermal state. Its lifecycle state was Unknown
  because Instruments attached to an existing process; screen identity relies
  on the owner's confirmation. Brief hitches recur, but no specific app-code
  bottleneck or user-visible severity has been established.
- Allocations recorded 90.98 seconds; the owner reported five Home/return cycles
  during the exercise. Instruments showed repeated graphics-allocation rises
  and falls late in the recording, with a broadly level heap-only chart rather
  than an obvious increasing staircase. Transitions were not individually marked,
  so exact alignment of all five user actions has not been independently proved.
- In the whole-run Created & Persistent statistics, All Heap & Anonymous VM was
  60.34 MiB persistent (15.26 MiB heap, 45.08 MiB anonymous VM). IOSurface accounted
  for 45.05 MiB: 3 persistent allocations and 12 transient allocations out of 15.
  Total allocated bytes across the interval were 484.37 MiB, not peak or resident
  memory. These attached-recording statistics do not describe all pre-attach
  image allocations or establish leak freedom.
- CPU/hitch/allocations captures ran sequentially, not together. No app changes
  or benchmark-driven improvement claims have been made. Auth-cycle, launch,
  and rollover allocation checks remain pending. The subsequent Reduce Motion
  comparison is documented below.
- Traces: `/tmp/whiskers-device-card-cpu-20260910.trace`,
  `/tmp/whiskers-device-card-hitches-20260910.trace`, and
  `/tmp/whiskers-device-card-allocations-20260910.trace`.
  Allocations heap statistics were inspected in Instruments because the CLI TOC
  did not expose a heap-summary table. CPU/frame XML exports remain in `/tmp`.
- Repeat trace: `/tmp/whiskers-device-card-hitches-repeat-20260910.trace`;
  exported hitch/thermal evidence: `/tmp/whiskers-device-card-hitches-repeat.xml`.

### Physical Reduce Motion Comparison (September 10)

After the owner reported enabling Reduce Motion and returning to the card, the
same app process (10991) was used for separate 30-second CPU and Animation Hitches
captures. Both recordings completed normally; no application code changed.

- CPU Profiler contained zero CPU-profile sample rows and no potential-hang rows
  in a 31.06-second envelope, compared with 1,308 samples in the motion-enabled
  card baseline. Thermal state remained Nominal. This is consistent with reduced
  sampled work, not a CPU utilization measurement or proof of zero work.
- The animation trace had no hitch rows and nominal thermal state. It still
  contained 828 frame-lifetime records; those aggregate records do not prove
  the app's decorations stopped or attribute every frame to the app.
- Instruments reported Unknown lifecycle state for the attached process. The
  owner subsequently confirmed that the card remained visible and the phone
  unlocked throughout, sparkles stopped with Reduce Motion on, and sparkles
  resumed after restoring it to off. This closes this card's live motion
  comparison; visibility and visual behavior are owner-observed evidence, not
  independently recorded UI observations or full accessibility sign-off.
- Traces: `/tmp/whiskers-device-card-reduced-cpu-20260910.trace` and
  `/tmp/whiskers-device-card-reduced-hitches-20260910.trace`.
  Exports: `/tmp/whiskers-device-card-reduced-cpu.xml` and
  `/tmp/whiskers-device-card-reduced-frames.xml`.

### Physical Auth-cycle Allocations (September 11)

The same optimized app build was relaunched before recording. This trace reports
iOS 26.6.2 (23G90), unlike September 10's iOS 26.6.1 baseline; do not treat these
different exercises/OS versions as a controlled before/after comparison.

- Allocations attached to PID 1010 with a 180-second limit and completed normally
  (181.798-second envelope). The owner reported completing three sign-out/sign-in
  cycles, pausing on the card after each, and leaving it open afterward. Password
  entry stayed on-device. Cycle boundaries were not independently marked.
- Whole-run Created & Persistent statistics: 75.85 MiB All Heap & Anonymous VM,
  consisting of 15.78 MiB heap and 60.08 MiB anonymous VM (rounded values).
  There were 102,325 persistent and 3,939,791 transient allocations. Total bytes
  allocated over the interval were 1.39 GiB, not peak memory or resident memory.
- IOSurface retained 45.05 MiB across 3 allocations, with 35 transient allocations
  out of 38. The SwiftUI layer-delegate VM category retained 10.55 MiB across
  5 allocations, with 72 transient allocations out of 77.
- The whole-run heap-only graph showed modest activity-related rises followed
  by a lower, broadly flat idle tail. The combined heap/VM graph rose during the
  exercise and settled below its activity peaks. No sustained idle-tail growth
  was visible at this scale; this does not exclude per-cycle retention, identify
  allocation ownership, or establish leak freedom.
- The attached recording does not account for all pre-attach image allocations.
  No source-level retention defect or justified optimization has been established.
  Startup/image-provider and day-rollover allocation checks remain open. This
  capture alone does not close overall performance or physical-device acceptance.
- Trace: `/tmp/whiskers-device-authcycles-allocations-20260911.trace`.
  Metadata: `/tmp/whiskers-device-authcycles-allocations-20260911-toc.xml`.
  Heap statistics and graph were inspected in Instruments; the CLI metadata
  does not expose the allocation summary. The recording has stopped; no new
  app code or tests were added for this documentation-only checkpoint.

### Startup Attempt and Isolated Harness (September 11 Evening)

- Owner confirmed the signed-in card was visible, with Reduce Motion and Low
  Power Mode off. The app's verified process (2943) was terminated for a controlled
  relaunch under Allocations. Instruments reported launching PID 2946 and saved
  a 31.540-second trace, but the owner reported the app never visibly opened.
- Saving was unusually slow and logged a dyld overlapping-library timeline
  warning. The trace eventually saved with exit code zero; a later termination
  attempt found that the profiler had already exited. Metadata export and opening
  in Instruments succeeded, but tool success does not override failed visual
  confirmation. Do not treat this as a valid signed-in startup or timing baseline.
- For diagnostic provenance only, the table reported 79.63 MiB persistent heap
  plus anonymous VM, including 12.10 MiB heap and 67.53 MiB anonymous VM. These are
  not RSS/peak measurements and do not establish expected visible-app behavior.
- Trace: `/tmp/whiskers-device-startup-allocations-20260911-1837.trace`;
  metadata: `/tmp/whiskers-device-startup-allocations-20260911-1837-toc.xml`.
- Rather than repeatedly retrying the launch path, the owner approved
  `tools/PerformanceHarness`: a separate developer app, no Firebase dependency,
  no real account/session access, and no shipping-target changes. It uses the
  real provider, card view, manifest, and assets, with injected Gregorian UTC
  dates instead of changing the phone clock. It does not use `DailyContentState`
  or exercise real foreground event delivery.
- Harness Release build and strict/deep signature verification passed. The final
  build has no logged compiler/build warnings. Installed separately as
  `com.example.kenwidemon.dailywhiskers.performanceharness`. Manifest validation
  confirmed the chosen 31 dates cover all 31 unique image selections per pass.
  The exercise makes two passes, two seconds per image, then a 20-second idle
  tail, with signposts. It initializes the provider only after the Start button,
  so an attached profiler can capture initialization and subsequent rendering.
- Harness results follow below. Shipping-app regression tests were not rerun
  for these isolated harness/documentation changes; the latest full result
  remains September 9's 46 tests in seven suites. The historical simulator counts
  below describe their original runs, not the latest suite.

### Isolated Image Exercise Results (September 11 Evening)

- The owner confirmed the separate harness was visible, but initially started
  it before recording. That warm-up was discarded: the harness was relaunched
  in a fresh process (2964), then Allocations attached before the owner was
  instructed to tap Start. The owner later confirmed the completion message.
- The 210-second recording completed normally (211.014-second envelope), on
  iPhone 17 Pro Max / iOS 26.6.2 (23G90), with no warning in the capture log.
  The owner had confirmed Reduce Motion and Low Power Mode off for this session;
  no setting changes were requested. The harness uses the real rendering code
  from `37f9e00` plus the separate driver included with this evidence.
- Whole-run Created & Persistent statistics reported 250.91 MiB All Heap &
  Anonymous VM: 7.66 MiB heap and 243.25 MiB anonymous VM. Of 2,212,256 tracked
  allocations, 30,152 remained persistent. Total allocated bytes were 1.18 GiB,
  not peak memory or resident memory.
- IOSurface accounted for 226.12 MiB across 34 persistent allocations (one
  transient, 35 total). SwiftUI layer-delegate VM accounted for 10.33 MiB across
  7 persistent and 59 transient allocations. Do not equate these categories
  directly with a proven per-image cache owner without stack/ownership analysis.
- The combined graph showed an initial rise, followed by a broadly flat later
  portion through the idle tail. The heap-only graph showed early spikes that
  settled. This is consistent with warmed graphics/image reuse, not proof of
  leak freedom, cache eviction under pressure, or safe usage on smaller devices.
- Signpost export retained only the last 15 image events (pass 2, days 17-31),
  starting at 112.625 seconds, plus the end of pass 2 at 143.348 seconds. The
  complete idle interval was present from 143.349 to 163.403 seconds, followed
  by the exercise end. Earlier provider/pass-start markers were absent in both
  the exported table and visible Points of Interest track. The reason for missing
  markers was not established; do not report measured provider-init time or
  exact pass-to-pass allocation deltas. Two-pass completion is owner-observed
  evidence supported by the bounded driver, not a fully retained marker sequence.
- This closes the initial accelerated image-change observation, not real
  foreground rollover or startup profiling. No shipping optimization is made:
  the retained graphics allocation warrants future memory-pressure/lower-memory
  device testing, not speculative cache replacement based on this run alone.
- Trace: `/tmp/whiskers-device-harness-images-20260911.trace`.
  Metadata and markers: `/tmp/whiskers-device-harness-images-20260911-toc.xml`
  and `/tmp/whiskers-device-harness-images-20260911-signposts.xml`. Statistics
  and graphs were inspected in Instruments. All recording/export commands ended.

### Visibly Confirmed Initialization Follow-up (September 11)

- Instruments' graphical App Launch template was configured for the connected
  iPhone, installed Daily Whiskers app, Normal launch (not Background Fetch),
  and automatic stop after 20 seconds. It produced a run for PID 3128, but the
  owner again reported that the app never visibly opened. Saved as
  `/tmp/whiskers-device-normal-launch-inconclusive-20260911.trace`; no successful
  startup result or timing is claimed from this second Instruments-owned launch.
- Used a different, supported path: `devicectl device process launch` with
  `--terminate-existing --start-stopped --activate`, then attached Allocations to
  the fresh process (3133). After the recorder reported active, `devicectl device
  process resume` successfully sent SIGCONT. The owner confirmed the signed-in
  daily card was visible after resume. The app/account/data were not replaced.
- The 45-second recording completed (46.338-second envelope), on the same
  iPhone 17 Pro Max / iOS 26.6.2 (23G90) and unchanged optimized app. Resume was
  reported at 19:03:20.354 local time, after the trace start at 19:03:18.160.
  The intentional pause and attached instrumentation preclude a natural cold-
  launch timing benchmark or a claim that every pre-attach allocation was seen.
- The saved trace opened and metadata exported successfully, but the recorder
  repeated the overlapping-dyld-library timeline warning. Its impact on symbol/
  timeline attribution is not established. Treat the following as qualified
  allocation-table observations, not a clean source-level startup analysis.
- Whole-run Created & Persistent statistics: 78.92 MiB All Heap & Anonymous VM,
  including 11.78 MiB heap and 67.14 MiB anonymous VM. There were 44,598 persistent
  and 628,146 transient allocations; cumulative allocated bytes were 247.17 MiB.
  IOSurface accounted for 51.17 MiB (5 persistent allocations), with 10.55 MiB
  in SwiftUI layer-delegate VM (5 persistent, 1 transient).
- The combined graph rose sharply near initialization and stayed broadly flat
  afterward. No sustained growth was visible at this scale. These are not RSS,
  peak memory, leak-freedom, provider-construction-count, or memory-pressure claims.
  No optimization is justified by this short observation alone.
- Trace and metadata: `/tmp/whiskers-device-paused-startup-20260911.trace` and
  `/tmp/whiskers-device-paused-startup-20260911-toc.xml`. Launch/resume command
  evidence: `/tmp/whiskers-paused-startup-launch.json` and
  `/tmp/whiskers-paused-startup-resume.json`. Recordings and export have stopped;
  no shipping code changed and no tests were rerun for this evidence-only update.

### Next Performance Decisions

1. Controlled initialization memory now has owner-visible evidence, qualified
   by the dyld warning and intentional launch pause. Natural cold-launch timing
   remains unmeasured; neither failed Instruments-owned launch is a valid timing
   baseline. Do not keep repeating the same failed launch path to force closure.
2. Image-change memory has bounded harness evidence. Real midnight/foreground
   integration, provider reconstruction, and memory-pressure behavior remain
   unmeasured. The isolated exercise is not a substitute for those checks.
3. Brief signed-in hitches were observed in September 10 captures; source-level
   attribution and user-visible severity are not established. No optimization
   or full performance sign-off is claimed. Energy, long-session, and lower-memory
   device measurements are outside this completed bounded exercise.
4. The owner authorized publishing this evidence and harness through the normal
   task PR into `codex/develop`. The broader physical-device accessibility/
   interaction acceptance checklist is still pending, not waived.

## Historical Step 5 Changes

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

## Signed-in Follow-up (September 5-6)

On revision `27737a5`, the iPhone 17e simulator displayed the signed-in daily
card. Fifteen one-second observations with the keyboard and password-save prompt
absent measured 3.7-7.5% CPU (mean 6.09%) and 403.61-403.70 MiB resident memory.
This is a short steady-state sample, not a leak or allocation test.

- After opening Settings and waiting ten seconds, five observations reported
  0.0% app CPU. Foregrounding retained the same app process and account session.
- Enabling Reduce Motion produced byte-identical card screenshots two seconds
  apart. Disabling it restored visible sparkle changes without relaunch.
  The original disabled setting was restored after the interrupted QA session.
- Across the actual local-day change from September 5 to September 6 (EDT),
  foregrounding changed the card from the devotion quote to `noble_temple_sentinel`,
  with "Stand firm in what feels true." and "conviction". This matches
  `20260906 % 31` in the bundled manifest. The process ID stayed unchanged.
- Instruments CPU Profiler initially failed to find the simulator process by PID.
  A device-targeted retry attached but stalled beyond its ten-second limit and
  was terminated. No completed Instruments result is claimed.

No application code changed in this follow-up. The prior 35-test result below
remains the latest regression run; tests were not rerun for documentation alone.

## Historical Simulator Follow-up Gaps

The signed simulator build and all 35 existing regression tests passed after the
changes. These tests cover auth/content behavior, not measured frame pacing.

This is the September 6 checkpoint, retained for provenance. The physical-device
sections above supersede the auth-cycle, idle-hitch, and card Reduce Motion gaps;
they do not establish complete performance acceptance.

- Signed-in GPU/frame-pacing, image allocations, rollover memory, and auth-cycle
  profiling remain unverified. The follow-up above supplies the signed-in idle CPU
  baseline, but not those deeper measurements. No user credentials or auth bypass
  were added for profiling; the existing signed-in session was preserved.
- Physical-device smoothness, frame pacing, energy use, and live reduced-motion
  acceptance remain required. Existing accessibility acceptance items are tracked
  separately in `accessibility-interaction-qa.md`.
- No shadow/compositing or image-format changes were made without evidence.
