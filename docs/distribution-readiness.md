# Distribution Record and Procedure

Current release status belongs in the [release checklist](release-checklist.md).
This document preserves candidate provenance and the procedure for a separately
approved replacement. Dates below identify recorded checks, not fresh reruns.

## V1.1 Candidate Provenance

The accepted V1.1 source is version `1.1 (3)` from
[PR #92](https://github.com/KenWidemon/daily-whiskers/pull/92), not the later
documentation commit. The following artifact checks were performed October 11,
2026; local artifacts were not rehashed during the October 12 documentation update
because the Mac was unavailable.

| Identity | Recorded value |
| --- | --- |
| Source commit | `f5413459e9b215a42816662e634ed8df3e7a53ad` |
| Source tree | `10ceb8376e4b4596d4e638712854c6703bb719c9` |
| Candidate tag | `v1.1.0-rc.2` approved; creation pending an annotated-tag-capable tool |
| Archive toolchain | Xcode 27.0 (27A266a), iPhoneOS SDK 27.0, locked dependencies |
| App/archive/dSYM UUID | `E66CD026-1560-3032-9EA6-E4CAB6A2B1A1` (arm64) |
| Original export IPA SHA-256 | `ea35d517a73391d1eec357103226f316612dd29b576f2a4447c11374c9598b7c` |
| Uploaded package IPA SHA-256 | `a0e7a59b47706958fd08487b6a1bd6a2f7c7fee49bf620910209ca130f3ebf9f` |
| Original archive file-manifest SHA-256 | `553fc7938563443b50b9c8f0a2091d1623e6979de248b48479b206c4fb3d7e02` |
| Apple build/upload identifier | `57062d5e-9d0b-4ab8-a486-91e4e1e56d80` |

[Exact RC CI](https://github.com/KenWidemon/daily-whiskers/actions/runs/38173753851)
passed 96 unit cases / 146 executions, five offline smoke cases, unsigned Release
simulator build and CI Gate, with zero failures, skips or expected failures.
The PR-head run also passed. CI used Xcode 26.6; it did not produce the signed
Xcode 27.0 distribution artifact.

Archive/export verification checked production Firebase configuration, identity,
Associated Domains, privacy manifests, encryption Boolean, diagnostic exclusions,
strict/deep signatures and matching app/dSYM UUIDs. Distribution used the existing
certificate `3CA55E826F7FC17DB76841664FEFF499906013BD` and profile
`eea6eaeb-6137-482b-96f5-97cbca8c7ca2`. Both expire September 10, 2027,
01:31:50 UTC (September 9, 21:31:50 EDT).

Apple validation succeeded October 11 at 21:44:54 UTC; upload succeeded without
errors at 21:47:46 UTC and returned `PROCESSING`. Organizer repackaged separately:
the original export is 74,379,740 bytes; the upload package is 74,379,739 bytes.
The preserved upload package matched Apple's logged MD5 and size, not a
server-side SHA-256. All 50 executable sections and the UUID matched the archive;
all non-executable resources matched the verified export. Original archive,
86 frozen build-2 files and 42 V1 files were unchanged at that verification.

Private evidence is retained in the build-3 artifact directory
`v11-artifacts/1.1-3-f5413459-20261011/provenance/`, including
`archive-verification.json`, `ipa-verification.json` and
`validation-upload-verification.json`. These are existing private receipts, not
files to commit. Upload acceptance alone did not establish processing completion;
subsequent selection and acceptance are recorded in the
[release checklist](release-checklist.md#v11-build-3-release-preparation).

### Preserve Build 2 and V1

Immutable `v1.1.0-rc.1` remains version `1.1 (2)`, source
`4d2956448d80ddc8cf08a430989370552b316874`, tree
`a379bf01116cb63a8fcd4a1e18370929376dca72`, annotated tag object
`ee52ec4c32bf1695e41a5a49e1e775c60ccbec92`. Its verified export SHA-256 is
`298c81ef75ef35f29c6b17a277f81649094d1d6baa5b0f8019d37a0d85d0ba79`.
Do not move that tag, overwrite either candidate, or rebuild/re-upload build 3
for documentation or ancestry bookkeeping. The V1 records below remain historical.

## Scope and Identity

- App Store Connect app ID: `6809050612`.
- Bundle ID: `com.example.kenwidemon.dailywhiskers`; team: `HYU33CNQ69`.
- Historical V1 submitted candidate: version/build `1.0 (1)`, iOS 17 minimum, iPhone and iPad.
- Build ID: `544c2ff8-c06c-4e03-84db-6bb8dc46b920`.
- `project.yml` is configuration source. Real Firebase configuration stays ignored;
  never distribute `ci/firebase-test-config.plist`.
- Earlier September 9 archives predate guest-first/VoiceOver work and are not RC1.
  Development-trunk changes after RC1 are not part of the submitted binary.

## RC1 Artifact Record (September 14, 2026)

| Identity | Recorded value |
| --- | --- |
| Immutable tag | `v1.0.0-rc.1` |
| Source commit | `20ae9cd3d664c3c412a2489ea7304449f1e0b8e2` |
| Source tree | `6391e24d23c0bb7c5026809ea4da3c77b521ef99` |
| Toolchain | Xcode 26.6 (17F113), iPhoneOS SDK 26.5, locked dependencies |
| Archive/executable/dSYM UUID | `9B7663E9-70C8-3AF5-A140-5EA567CD5A6D` (arm64) |
| Original export IPA SHA-256 | `32a4bba9f7fcf63a639c558e6f800effad7a30b16ed0f19c9e8ffe5f0af2bbb4` |
| Upload-package IPA SHA-256 | `ed8f46d7c57177cac6449677a47e851570e5542214daefdec7f8ab05cd33d75f` |
| Original archive file-manifest SHA-256 | `0e33661bed4479b032d2ecd42696eb938caa2b3058f9b54df9865781a848fe3f` |

PR #46 created RC1 from approved develop revision
`00f246689d876a8ff28718960b606cb40843c037`, preserving merge ancestry and tree
identity. The tag is immutable; the archive was built from it, not a later merge.

Recorded verification: XcodeGen reproduced the project; RC CI and 57 tests in
eight suites passed on iPhone 17e / iOS 26.5 Simulator. Signed Release archive,
App Store export, strict/deep signature checks, and Xcode server validation passed.
This is not a full UI pass or an App Review approval. Known warnings were skipped
App Intents extraction and the Firebase module/dependency-scan warning.

Packaged identity, orientation declarations, real Firebase configuration, daily
JSON/assets and app/dependency privacy manifests were checked. Encryption is
Boolean false for `ITSAppUsesNonExemptEncryption`, not a string or missing key.
The export profile had `get-task-allow=false`, no development-device list, and
September 10, 2027 expiration. Targeted checks found no debug account helper or
screenshot/profiling-harness markers; this was not an exhaustive security audit.

### Local Artifacts

Paths are relative to the original project checkout and ignored by Git. Verify
existence before use; preserve artifacts rather than rebuilding under the same tag.

- `build/releases/v1.0.0-rc.1/DailyWhiskers.xcarchive`
- `build/releases/v1.0.0-rc.1/export/DailyWhiskers.ipa`
- `build/releases/v1.0.0-rc.1/upload-package/DailyWhiskers.ipa`
- Same directory: `provenance.json`, `archive-file-sha256.txt`, `UnitTests.xcresult`,
  archive/export/upload logs, validation/upload distribution logs and options.
- `build/releases/v1.0.0-rc.1/visual-parity/`: per-card captures/provenance and comparison.

The uploaded IPA is a separately exported package from the same validated archive,
not byte-identical to the earlier local export. Upload added distribution metadata
to the archive's outer Info.plist; app/dSYM file hashes and earlier export stayed
unchanged. The manifest hash identifies a file-content list, not a directory hash.
Do not claim the entire post-upload archive container remained byte-identical.

### RC-Source Screenshot Comparison (September 14, 2026)

All six fresh Release previews from RC1 matched the approved September 12 raw
captures in scoped layout/content inspection: Celestial, Forest, Cozy on iPhone
17 Pro Max and iPad Pro 13-inch (M5), Simulator iOS 26.5, default text size.
Quote wrapping, crop, vibe, frame, Settings and safe areas passed. Animation phase
and status-bar indicators differed; this is not pixel equality or physical QA.
Approved raw/export hashes stayed unchanged; no replacements were uploaded.

## Distribution and Promotion History

- September 14, 8:47 PM EDT: Xcode reported successful server validation.
- September 14, 9:41 PM EDT: owner-authorized upload succeeded from the validated
  archive with `manageAppVersionAndBuildNumber=false`. App Store Connect showed
  upload Complete and the expected build ID. Build 1 is used; do not upload it again.
- September 28 audit: `1.0 (1)` Testing with V1 Internal Testing and Family & Friends,
  eight invitations and six installations. These counts are dated observations.
- PR #65 merged final acceptance evidence into RC. PR #66 promoted RC into main at
  `090a4c9d6bbe29f488410f2ea32b0d83dad437c4`, matching RC head
  `61531ecfb42e9f83f445772dc75aec2fbd48b998`; both listed CI checks passed.
  Only seven Markdown files differed from frozen RC1; app/project/test/configuration
  and iOS workflow Git objects matched. No V1.1 source entered that promotion.
- PR #67 synced main history to develop at
  `ba181db5c180f199fcee17f90b48680917c0f2ad` with passing CI. Later trunk work is
  independent of the frozen candidate.
- September 28: existing `1.0 (1)` was attached, saved and reload-verified with
  manual release. Free/U.S.-only scope, Mac/Vision Pro opt-outs, active agreement/DSA,
  approved metadata, screenshots and public pages passed the visible preflight.
- Initial App Review submission succeeded at 1:58 PM EDT, observed Waiting for
  Review under `c7648ecf-cc4a-4d87-b014-d7c5e1a8b9e4`. Later rejection and
  owner-reported resubmission are in the [review record](app-review-response-2-1.md).

## Reproduce Without Uploading

Only for a newly approved candidate, not an instruction to replace RC1. Start
from the frozen approved `release/rc` commit with real ignored Firebase config.
Use fresh output paths, a new available build number for a changed binary, and
record source/toolchain/configuration. Never overwrite accepted artifacts.

```sh
xcodegen generate
xcodebuild archive -project DailyWhiskers.xcodeproj \
  -scheme DailyWhiskers -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/whiskers-distribution.xcarchive \
  -onlyUsePackageVersionsFromResolvedFile

xcodebuild -exportArchive \
  -archivePath /tmp/whiskers-distribution.xcarchive \
  -exportOptionsPlist ci/ExportOptions-AppStore.plist \
  -exportPath /tmp/whiskers-distribution-export \
  -allowProvisioningUpdates
```

The checked-in options use `destination=export`, automatic signing and no automatic
version/build update. Provisioning updates can obtain signing assets through Xcode;
export does not upload or approve the app. Verify signatures, embedded profile,
identity, Firebase config, content, privacy manifests, encryption declaration and
symbol UUIDs. Run Xcode **Validate App** separately. Upload, reviewer submission,
legal acceptance and public release each require the applicable owner authorization.

For source promotion and fixes, follow [branching strategy](branching-strategy.md).
For open gates and scoped acceptance, use [release checklist](release-checklist.md).
Old failed signing/profiling attempts are in [historical recovery](README.md#historical-recovery),
not current prerequisites to repeat.
