# Card Image Import Guide

## Current Asset Workflow

The source of truth is each card's `imageName` in
`DailyWhiskers/Resources/daily_whiskers_content.json`, not a photo's sequence number.
Paths here are relative to the repository root. The current manifest contains
31 cards; confirm the count from JSON after content edits.

File location pattern:
- `DailyWhiskers/Assets.xcassets/<imageName>.imageset/<imageName>.png`
- Each imageset also needs a `Contents.json` referencing its exact PNG filename.

Keep `imageName`, imageset name, and file reference consistent. Replace existing
artwork in its named imageset; do not re-create a loose `Photos` folder or rename
the collection by order. For a new card, add its manifest entry and named imageset,
then run bundled-content/asset-integrity tests. Reordering or changing the number
of cards changes date selection (`YYYYMMDD % cards.count`).

Artwork is portrait PNG, currently 1024 x 1536. The ritual card uses a rounded,
portrait, content-sized frame with scaled-to-fill artwork; it is **not a square**.
Keep the subject clear of edges and the lower quote overlay, and check cropping
on phone/iPad and at large text sizes before approving replacements.


Keep maintenance notes in docs, not bundled Resources. Original sequential-import
mapping is recoverable through [documentation history](README.md#historical-recovery).
See [app setup/tests](../DailyWhiskers/README.md) and the [release checklist](release-checklist.md).
