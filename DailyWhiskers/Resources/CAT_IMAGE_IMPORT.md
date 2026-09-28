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

## Historical First-Import Mapping (Completed)

The following `cat - N.png` names belonged to the original import. This is retained
as provenance only, not a request to rename current assets. The original mapping
followed the manifest's order at import time:
- `cat - 1.png` -> `arcane_spellbook_reader.png`
- `cat - 2.png` -> `arcane_moonlit_diviner.png`
- `cat - 3.png` -> `arcane_rune_engraver.png`
- `cat - 4.png` -> `arcane_orb_seer.png`
- `cat - 5.png` -> `arcane_library_guardian.png`
- `cat - 6.png` -> `arcane_star_chart_astrologer.png`
- `cat - 7.png` -> `forest_lantern_bearer.png`
- `cat - 8.png` -> `forest_elven_scout.png`
- `cat - 9.png` -> `forest_ancient_tree_guardian.png`
- `cat - 10.png` -> `forest_moss_shrine_watcher.png`
- `cat - 11.png` -> `forest_whispering_woods_pathfinder.png`
- `cat - 12.png` -> `alchemy_cauldron_stirrer.png`
- `cat - 13.png` -> `alchemy_crystal_distiller.png`
- `cat - 14.png` -> `alchemy_herb_mixer.png`
- `cat - 15.png` -> `alchemy_mist_conjurer.png`
- `cat - 16.png` -> `alchemy_stardust_collector.png`
- `cat - 17.png` -> `noble_crowned_feline_protector.png`
- `cat - 18.png` -> `noble_cloaked_castle_watcher.png`
- `cat - 19.png` -> `noble_sacred_relic_keeper.png`
- `cat - 20.png` -> `noble_temple_sentinel.png`
- `cat - 21.png` -> `noble_dawnlight_herald.png`
- `cat - 22.png` -> `celestial_constellation_watcher.png`
- `cat - 23.png` -> `celestial_crescent_moon_companion.png`
- `cat - 24.png` -> `celestial_star_map_traveler.png`
- `cat - 25.png` -> `celestial_aurora_spirit_guide.png`
- `cat - 26.png` -> `celestial_dawnlight_dreamer.png`
- `cat - 27.png` -> `cozy_rainy_window_mystic.png`
- `cat - 28.png` -> `cozy_fireplace_sage.png`
- `cat - 29.png` -> `cozy_teacup_tarot_reader.png`
- `cat - 30.png` -> `cozy_lantern_lit_night_wanderer.png`
- `cat - 31.png` -> `cozy_candlelit_study_companion.png`

For app setup and tests, see the [app README](../README.md). For current release
work and screenshot parity, see the [release checklist](../../docs/release-checklist.md).
