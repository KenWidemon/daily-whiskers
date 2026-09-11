# Isolated Image Profiling Harness

Developer-only app with a separate bundle ID. It is not included in the shipping
project, has no Firebase dependency/configuration, and cannot access the app's
authentication session. The owner approved this harness for bounded profiling.

It compiles the real content provider, model, and ritual-card view and bundles the
real catalog/manifest. Start it in a fresh process, attach Allocations, then tap
**Start Two-Pass Image Check**. Provider initialization occurs after that tap, so
an attached capture includes manifest validation and image resolution.

The exercise selects January 1-31, 2026 in a fixed Gregorian UTC calendar, twice,
at two seconds per card, followed by a 20-second idle tail. With the current
31-card manifest this visits every selection index each pass. It never changes
the system clock. Points of Interest mark provider initialization, both passes,
each image selection, and the idle tail. Leave the app foreground/unlocked;
backgrounding invalidates the run. Relaunch before a repeat to avoid mixing
fresh-process and warmed image-cache results.

From the repository root:

```sh
xcodegen generate --spec tools/PerformanceHarness/project.yml
xcodebuild -project tools/PerformanceHarness/WhiskersPerformanceHarness.xcodeproj \
  -scheme WhiskersPerformanceHarness -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/whiskers-performance-harness-build \
  -allowProvisioningUpdates build
```

Install/profile only this separate harness bundle. Do not upload it to App Store
Connect. It uses development signing; provisioning may require the owner's Xcode
account. No generated Xcode project or raw trace is committed.

## Interpretation Limits

- This is accelerated provider/image-rendering coverage, not a real midnight or
  foreground-lifecycle test. It does not instantiate `DailyContentState`, router,
  navigation, auth, or account settings. Existing unit tests cover day selection
  and foreground refresh logic separately.
- The provider is constructed once per exercise. This does not measure shipping
  parent-view reconstruction or prove it avoids repeated manifest loads.
- Compare first/second pass and idle tail in the same capture. Stable framework
  caches are not automatically leaks; total allocated bytes are not peak/RSS.
- Respect current Reduce Motion and record it with device/OS/build information.
  Do not extrapolate a short capture to energy use or low-memory-device behavior.
