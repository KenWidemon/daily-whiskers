# Screenshot Previews

Owner authorized an isolated capture setup on September 12, 2026. This is not the
retired performance harness, a shipping target, or an authentication test.

`prepare.rb` creates a fresh temporary Xcode project. Production Swift sources are
copied unchanged except the app entry point and router, which are replaced by
`CaptureApp.swift`. No Firebase configuration is copied and no account credentials
are requested or used; account operations are disabled. The selected production card is copied unchanged into
a one-card temporary manifest, so the real provider and views render it without
changing the device clock. The full shipping manifest is untouched.

The generated target is simulator-only, skips installation into archives, and
has a separate bundle ID. FirebaseAuth is linked only because the unchanged error
mapping sources use its types; Firebase is never configured. Always build Release
to omit debug UI and the existing debug-only test-account environment helpers in AuthView.
Those source declarations are preserved by the byte-for-byte copy, not used by
the capture app. Do not use this app for functional acceptance or upload it.

## Prepare and Build

Requirements: Xcode, XcodeGen, macOS Ruby, and resolved Swift package dependencies.

```sh
ruby ci/screenshots/prepare.rb celestial_constellation_watcher
# Use the temporary directory printed by the script as CAPTURE_PROJECT.
xcodebuild -project "$CAPTURE_PROJECT/WhiskersScreenshots.xcodeproj" \
  -scheme WhiskersScreenshots -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/whiskers-screenshots-derived build
```

Switch cards in the same temporary project and rebuild to reuse build products:

```sh
ruby ci/screenshots/select-card.rb "$CAPTURE_PROJECT" forest_lantern_bearer
# Repeat the build, then capture; next select cozy_fireplace_sage and rebuild.
```

Keep each `capture-provenance.json` beside its PNGs. It records the source revision,
exact source hashes, original manifest hash, and selected card. Verify source
hashes against the accepted release candidate before final export.

## Capture Checklist

- Install only on explicitly selected simulators using the separate bundle ID.
- Capture portrait iPhone 17 Pro Max and iPad Pro 13-inch independently.
- Use English (U.S.), default text size, full-screen iPad, and no keyboard/menus.
- Set only the simulated status bar to 9:41/full battery; do not change the clock.
- Leave Reduce Motion off for the ordinary UI; sparkle pixels may vary by frame.
- Launch normally for the card; pass `--login` for the optional empty login view.
- Wait for layout and entrance animations to settle before `simctl io screenshot`.
- Inspect all captures for clipping, legibility, correct quote/vibe, and private data.
- Preserve native, unedited PNGs. Compose approved captions separately, never
  insert them into or otherwise invent app UI.
- Obtain owner approval of card choices and previews before final exports.
- Clear status-bar overrides and shut down the capture simulators afterward.

Native portrait targets are 1320 x 2868 (iPhone) and 2064 x 2752 (iPad). Final
uploads must have no alpha channel; verify dimensions and format before upload.
See [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications),
checked September 12, 2026. No upload or release acceptance is implied by previews.

## Compose and Export

After card/order approval, use the macOS-native compositor. It adds the approved
captions outside each complete screenshot, with uniform scaling and no cropping,
generative image edits, UI retouching, or invented device frames.

```sh
swift -module-cache-path /tmp/whiskers-screenshot-swiftcache \
  ci/screenshots/compose.swift build/screenshots/2026-09-12
```

Requires macOS AppKit, the Baskerville font, and the Swift toolchain. The input
directory must contain `capture-index.json` and the six approved raw PNGs. The
script verifies input hashes/dimensions and text bounds, then checks the decoded
output dimensions and opacity. Original files are not rewritten.

Outputs under `compositions/`:

- `iphone/` and `ipad/`: three opaque sRGB PNGs each, in approved order.
- `iphone-review.png` and `ipad-review.png`: reduced contact sheets for review
  only, not App Store uploads.
- `export-index.json`: captions, dimensions, input/output hashes, renderer hash,
  and pending approval status. Retain it with the exports.

Final composition approval and comparison against the accepted release candidate
are still required. Re-rendering replaces composition outputs and resets their
manifest to awaiting approval; do not treat earlier approval as covering edits.
