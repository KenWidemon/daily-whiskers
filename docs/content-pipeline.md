# Card Image Import Guide

## Current Asset Workflow

The source of truth is each card's `imageName` in
`DailyWhiskers/Resources/daily_whiskers_content.json`, not a photo's sequence number.
Paths here are relative to the repository root. The current manifest contains
31 cards; confirm the count from JSON after content edits.

File location pattern: `DailyWhiskers/CardOriginals/<imageName>.png`.
XcodeGen copies this directory as a folder resource without processing its PNGs.
Only the app icon belongs in `Assets.xcassets`; do not add duplicate card imagesets.

Keep `imageName` and the original PNG filename consistent. Replace existing
artwork with the exact accepted file; do not recompress it or rename the collection
by order. For a new card, add its manifest entry and original PNG, then run
bundled-content and retained-artwork integrity tests. Verify source and built-app
checksums after a clean build. `BundledCardArtwork` is the shared loader for
validation, display, previews and sharing. Saved versions retain their own bytes.
Reordering or changing the number of cards changes date selection
(`YYYYMMDD % cards.count`).

Artwork is portrait PNG, currently 1024 x 1536. The ritual card uses a rounded,
portrait frame that fits the full artwork above the quote panel; it is **not a
square**. Ordinary phone portrait layouts compact the quote panel and fit the
uncropped artwork into the remaining viewport height, preserving its aspect ratio.
Accessibility text, landscape and exceptionally long content can scroll. The
compact layout omits the decorative quote marks and transition fade; other layouts
retain their existing treatment. Check complete artwork and text on small phones,
iPad and large text sizes before approving replacements.


Keep maintenance notes in docs, not bundled Resources. Original sequential-import
mapping is recoverable through [documentation history](README.md#historical-recovery).
See [app setup/tests](../DailyWhiskers/README.md) and the [release checklist](release-checklist.md).
