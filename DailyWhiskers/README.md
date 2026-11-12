# Daily Whiskers (SwiftUI)

Daily Whiskers is an iOS SwiftUI app that shows one curated cat card per day, with optional Firebase email/password accounts.

Documentation entry point: [documentation map](../docs/README.md).
For current remaining work, use only the [release checklist](../docs/release-checklist.md);
testing guidance preserves scoped evidence and open risks, not separate roadmaps.

## Current Behavior
- The daily card opens immediately without sign-in, including while Firebase restores
  its session. Guest access does not create a Firebase anonymous account.
- `AppRouter` tracks the account session; it does not gate daily content.
- Settings offers optional Sign In for guests, or Log Out and Delete Account for
  signed-in users. Privacy and Support are always available.
- Optional auth UI supports:
  - Sign In (email/password)
  - Dedicated Create Account form (email/password)
  - Forgot password (uses the entered email; no password required)
  - Debug-only "Use Test Account"
- Daily content is selected deterministically from local date:
  - `YYYYMMDD % cards.count`
- Daily content refreshes on foreground, significant clock changes and local-day
  notifications; a 30-second foreground check also detects midnight.
- Signed-in Settings offers password-confirmed permanent account deletion.
- Closing auth returns to the same daily card and discards unfinished credentials.
  While an account sheet is active, its underlying Settings menu is hidden from
  accessibility; dismissal restores Settings focus only when no replacement sheet
  is active. This avoids requesting background focus during account presentation.
  Close/swipe dismissal is disabled while an auth request is running. Successful
  sign-in or account creation dismisses auth. Logout and deletion return to guest
  access without removing the daily card or automatically reopening sign-in.

## Stillness Mode

**Settings > Stillness Mode** opens a small, guest-accessible motion settings sheet.
The native toggle defaults off and persists in local app preferences across launches
and account transitions. No account or cloud sync is involved. The effective rule is
**Stillness Mode OR system Reduce Motion**; switching the app setting off cannot
override the system. Both preferences update already-open surfaces.

Today, Bonus, saved-card detail and sign-in/registration use calm gradient backgrounds
without decorative sparkles when stillness is effective. The auth glow becomes static.
Those branches contain no animation timelines; essential loading feedback is retained.
The animated branches still pause when the scene is inactive. The saved collection
already uses a static background. Card content, layout, exports and contrast treatments
are unchanged. This adds only a focused sheet to the existing Settings menu; it does
not implement the separate Settings redesign or Daily Den.

See [Stillness acceptance](../docs/testing.md#stillness-mode).

## Bonus Card

The navigation bar's **Today** menu offers **Open Bonus Card**, an optional complete
cat-and-quote moment for guests and signed-in users. **Bonus > Return to Today**
restores the unchanged daily card. Both use the shared full-card renderer and the
same monochrome Save control; bonus sharing uses the existing export pipeline.
There is no quota upgrade, account requirement, cloud sync or date-browsing UI.

The allowance key is a Gregorian `YYYY-MM-DD` in the current local time zone; the
zone is recorded as provenance but is not part of identity. Each first successful
request atomically retains the selected content and date reference. Relaunch opens
Today; opening Bonus again retrieves the exact retained version. Navigation retains
the open bonus, while changing local date returns the main view to Today. Revisiting
a date after travel or a clock change reopens its original bonus; crossing into a
previously unused date permits that date's one bonus. This is a local calendar policy,
not a rolling 24-hour allowance or a mechanism to prevent manual clock changes.

New selections use the validated bundled pack and exclude Today's stable cat ID,
exact quote and decoded artwork pixels. Candidates rank by a date-and-ID SHA-256
hash, preferring those absent from the seven most recently issued bonus records
(by issuance order, not date order). Quote and pixel comparisons prevent aliases
from bypassing recent avoidance. If all valid alternatives are recent, a recent
alternative is allowed; Today's artwork and quote are never relaxed. Missing or
invalid candidates are skipped. No distinct valid option or a failed write leaves
the allowance unused. Corrupt retained content stays unavailable with retry and a
return to Today; it is never silently replaced. After a content-pack update,
preservation of an existing date's exact bonus takes precedence over reselection.
An intact retained bonus can reopen even if Today or the current pack is unavailable.
Unreadable recent metadata is ignored for avoidance, and damaged retained versions
are skipped as new candidates; neither grants a reroll of the original date.

The permanent ledger survives clearing Favorites and account transitions. It stores
one reference per used date and deduplicates artwork/snapshots using the existing
repository. A device backup may include it. Removing the app's data or restoring an
older backup can lose later date references; there is no server-side enforcement.
See [bonus acceptance checks](../docs/testing.md#bonus-card).

## Saved Cards

Today, Bonus and saved-card details expose Share and Save/Remove in a native
Options menu. The original monochrome heart-eyes cat artwork stays on the menu's
save action: clear when unsaved, with a lower-trailing check badge when saved.
The destructive **Remove from Saved Cards** action becomes **Save Card** after
removal. The persistent Options trigger exposes the **Saved/Not saved** value and
returns accessibility focus after saving or dismissing sharing. The stacked-card
button remains separate collection navigation; Today/Bonus switching and Settings
remain separate controls. No extra Options menu is added to the collection list.
Saved cards appear in a guest-accessible, newest-first
collection labeled **On this device**, with uncropped artwork tiles on a centered,
adaptive grid. On iPad at ordinary text sizes, each tile reserves three quote lines
so neighboring tile edges align. Accessibility text sizes use one column and complete quote labels.
Reopen the full card, share its
retained version, or deliberately remove it with the secondary destructive action.
Saving an identical version again
keeps its original position; different artwork or quote versions remain separate.
Ordering uses a monotonic insertion sequence, independent of wall-clock changes.

The collection distinguishes loading, a successful empty/populated read, and an
unavailable read. Empty guidance appears only after a successful empty read.
Dismissing a read-error alert leaves an in-place **Retry**; it only reads the
collection again. A later failed refresh retains the last successful rows with an
explicit previously-loaded status. Errors never reset or recreate unreadable
storage. A successful save/remove/clear followed by failed readback retries the
read, without replaying the committed write.

Known limitation: Today/detail save-action labels and Clear eligibility still
reflect the last successfully read rows. After a read failure they can be stale
until recovery succeeds. This pre-existing behavior is not resolved by the
collection loading/error presentation change.

Compact portrait windows keep the phone quote typography and spacing. Artwork
uses its natural aspect ratio at the available card width; text is never truncated
or scaled down to force a fit. The visible window dimensions and measured content
choose between a stacked card and a wide two-column card. When a stack is too tall
and there is room for the full-size artwork plus a readable quote panel, artwork
stays on the left with the full quote and Vibe on the right. Narrow or short windows,
unusually long content and accessibility text use stacked scrolling instead of
shrinking artwork. Larger stacked presentations retain the tighter quote spacing.
Today, Bonus and saved detail reflow without changing the selected content or save
state. The export layout is independent of this
viewport adjustment. Today and saved detail use the same card renderer, including
the themed frame, quote treatment and Vibe pill. Saved detail supplies its retained
artwork, quote, vibe and archetype directly. **Saved Card Options** contains
**Share Saved Card**, the destructive **Remove from Saved Cards** action, and offers
**Save Card** after removal while the detail stays open. Its title changes from
**Saved Card** to **Card** after removal and returns on re-save; Share and options
labels also reflect whether the card is currently saved. Dismissing the menu changes
nothing. No persistent removal footer reserves card space, so matched device/text
conditions use the same available card size. Both surfaces include the same
vertical quote-panel padding.

The collection belongs to the installation, independent of sign-in, logout or
account deletion. **Settings > Clear Saved Cards** is disabled while the collection is empty or
storage is busy. Its eligibility updates after saving, removing or clearing cards.
When enabled, it requires confirmation and
removes favorites without clearing the current card or retained day selections.
Daily Whiskers does not upload or sync this collection. Normal device backups may
include it; restore depends on the user's available backup/settings. An older
backup can restore cards removed later. Clear does not erase existing OS backups.

`CardRepository` serializes SQLite operations in Application Support. Schema 1
contains artwork BLOBs, immutable snapshots, favorites, and a permanent local-date
ledger for bonus selections. Snapshot/artwork/favorite writes commit
atomically with foreign keys, rollback journaling and FULL synchronization. Errors
preserve prior committed state and offer Retry. There is no destructive reset for
unknown schemas. The first migration creates schema 1 transactionally; no released
Favorites schema precedes it. Future migrations must preserve all four tables in
one transaction. `backup(to:)` produces a consistent SQLite copy for restoration
checks; it is not an app cloud backup feature.

Snapshot identity uses stable card ID plus a SHA-256 content revision over
versioned, length-prefixed UTF-8 displayed fields, exact quote identity/revision,
and a fixed sRGB RGBA8 pixel digest including dimensions. It excludes occurrence,
date, image name, manifest order and styling. Existing single quotes use a stable
`legacy:<cardID>` quote ID and exact-text checksum revision; explicit quote
identities can be supplied later without changing old snapshots. Bonus selection uses these same retained snapshots; no independent quote rotation
is introduced.

Original PNG bytes are stored once per checksum, verified on import/read and
never re-resolved through a mutable asset name. The current display and save
capture use the same packaged original bytes. A missing/corrupt saved card remains
visible with an unavailable/retry state; it never substitutes current artwork.
Cleanup retains snapshots referenced by favorites, date records or an
active repository share lease. The UI also holds a complete immutable card during
an open detail/share/retry. Thumbnails are generated only for visible rows and
kept in memory; there is no durable thumbnail cache. Exports remain memory-only.

The build includes `DailyWhiskers/CardOriginals` as a folder resource, preserving
source PNG bytes without asset-catalog processing. Manifest validation, Today,
previews, capture and sharing all use this one artwork source. The asset catalog
contains only the app icon. Future artwork integration must keep image names
stable and copy exact accepted originals; verify packaged checksums after a clean
build. Never recompress retained originals or bundle historical collections as a
retention strategy. Readback supports upright, single-frame images up to 4096
pixels per dimension. Measure bundle size and memory on each release candidate.

See [Saved Cards acceptance](../docs/testing.md#saved-cards).

## Sign In Password Visibility

Sign In starts masked. Its trailing Show/Hide Password control retains the native
field, typed value, selection and editing focus without submitting a request.
It exposes the current action and Hidden/Visible state to accessibility; password
fields expose only Empty/Password entered on focus, including while revealed.
The password masks on inactivity, auth requests and navigation; dismissing auth
clears the draft. Returning-user validation remains a six-character minimum, with
no new-account character rules. Both forms share the native fields and visibility
control, with explicit existing/new-password AutoFill traits.

The [combined physical acceptance procedure](../docs/testing.md#account-form-acceptance)
keeps DW-005 and DW-006 results separate and retains outstanding/deferred checks.

Automated results and remaining DW-006 acceptance limits are summarized in
[testing](../docs/testing.md#dw-006-development-evidence). Detailed execution
and review discussion belongs in [DW-006](https://github.com/KenWidemon/daily-whiskers/issues/55)
and [PR #70](https://github.com/KenWidemon/daily-whiskers/pull/70).

## Sharing Today's Card

The daily Options menu offers **Share Today's Card** (or **Share Bonus Card**)
to guests and signed-in users.
It captures the displayed immutable card when tapped, so a foreground/day change cannot
replace an in-flight export. The system share sheet receives a freshly rendered
image and a plain-text quote/vibe companion; the user chooses a destination and
confirms sending. There is no account requirement, upload, tracking, or automatic
posting in the app's sharing path. UIKit presents from the card screen's window
root, with the persistent Options control as the iPad popover anchor. Preview metadata uses only
the local export and branding, without a URL or network preview lookup.

The packaged app declares an add-only Photos purpose for a user-selected save
from the system sheet. It does not request photo-library reading or prompt for
access when opening the share sheet. Destination availability and successful
saving still require device acceptance; a purpose string alone is not proof.

The portrait export reuses `RitualCardPresentation`, including the archetype frame,
ordinary-phone serif quote treatment and Vibe pill. Its natural-height artwork and
measured text are independent of scroll position, screen size and Dynamic Type.
The app retains the user's requested text size and scrolling behavior; the export
uses a stable `.large` typography baseline. Artwork bytes, archetype, quote and
vibe are frozen before rendering, including retry after a failed share.

The proposed export format (pending owner visual approval) is 1080 pixels wide,
with a maximum height of 2400 pixels, opaque standard color and scale 1. Text grows
the image vertically rather than shrinking or clipping. Unsupported future text
that exceeds the bound fails with a retryable error before allocating the bitmap.
The packaged `Daily_Whiskers_App_Icon_FINAL_cropped.png` supplies the actual mark.
A deterministic green-channel alpha mask removes its purple tile and facial
cutouts, retaining the source silhouette/whiskers as white on transparency; no
logo geometry is redrawn. This monochrome treatment awaits visual review and appears at
72 × 72 pixels and 45% opacity, centered below the card with a 48-pixel gap and
54-pixel bottom inset. This dedicated watermark area cannot overlap artwork or
quote text. The frame, text and artwork have a 54-pixel outer inset. Content
additions must pass the sharing tests and visual review.

The app holds one export in memory, creates no temporary share files, and releases
its image reference when the sheet completes or is dismissed. UIKit/destination
apps manage any copies they create. A new bitmap excludes source image metadata;
only artwork, quote, vibe, and branding are exported, without account identifiers,
internal card IDs, date/location metadata, or Settings controls. Rendering or
activity errors offer retry; cancellation leaves the daily card usable.

Before release, confirm that the bundled artwork and quotes permit redistribution
through user sharing. Implementation and tests do not establish those rights.
See the [sharing acceptance procedure](../docs/testing.md#sharing-todays-card).

## Dedicated Registration

Create Account opens its own form without submitting Sign In credentials. Only
trimmed email is prefilled. Sign In's password is cleared on entry; registration
password is cleared when leaving that form or dismissing auth. Registration
keeps its input for correction after a failed request, without persisting or
logging credentials. Each form has one password field with AutoFill and a
Show/Hide control, and masks again when the app becomes inactive. Sign In uses the same
visibility control with existing-password AutoFill, while registration keeps
new-password AutoFill and its generation rules.

Registration validates email, password length and character types before calling
Firebase. Passwords are never trimmed or normalized. The password keyboard’s Done
action submits the form, using the same validation and request lock as the button.
Empty/invalid submissions show accessible feedback; navigation is available with empty Sign In fields.
Both forms retain one request lock and existing progress/error announcements.
Close and Back are disabled while a request runs; success closes auth through the
existing session listener and leaves the daily card in place.

Ken selected an Apple Account-style baseline for new accounts on September 28,
2026: at least eight characters, with an uppercase ASCII letter (A–Z), a lowercase
ASCII letter (a–z), and a number (0–9). Symbols and other Unicode characters are
allowed but not required. The existing maximum of 4096 remains. Registration
validation, visible guidance, and native [Password AutoFill rules](https://developer.apple.com/documentation/security/customizing-password-autofill-rules) use this baseline.
This is the selected length/character baseline, not a claim to reproduce Apple's
complete account security system or its common-password screening.

Length uses UTF-16 units to match [Firebase's reference policy validator](https://github.com/firebase/firebase-js-sdk/blob/main/packages/auth/src/core/auth/password_policy_impl.ts),
and the entered password is submitted with its exact UTF-8 input preserved.
Sign In retains its existing validation so older accounts remain usable.

Registration uses a single password to contain the cross-field loss reported in
[#86](https://github.com/KenWidemon/daily-whiskers/issues/86). Removing confirmation
reduces typo detection; Show/Hide offers optional visual review, and the existing
email-reset flow remains the recovery path. Neither is an equivalent nonvisual
confirmation check. This change does not establish that Apple’s popup dismissal
works in one field or that the separate [#85 Fill failure](https://github.com/KenWidemon/daily-whiskers/issues/85) is fixed.
Physical provider, manual-entry and accessibility acceptance remain required.

**Backend alignment remains pending.** The live Firebase `getPasswordPolicy`
response was rechecked October 2, 2026 UTC: minimum 6, maximum 4096, no required
character classes, enforcement `ENFORCE`; `forceUpgradeOnSignin` was not returned.
The new baseline is enforced by this registration form, not yet by Firebase.
Before shipping it as a service-wide
policy, configure Firebase's new-password requirements to minimum 8, uppercase,
lowercase, and numeric required; retain maximum 4096 and optional symbols.
Review existing-release/password-reset compatibility and preserve existing-user
sign-in before applying that live change. No Firebase settings were changed.

The frozen V1 source (`v1.0.0-rc.1`, `20ae9cd`) enables both Sign In and
Create Account at six characters, with no complexity guidance. A stricter server
policy therefore changes V1 behavior immediately: previously eligible registration
input can fail, and its `weakPassword` message incorrectly recommends six characters.
Other unmapped service errors produce generic retry feedback. V1.1 has the new
guidance and a policy-neutral backend rejection message, but cannot repair already
installed V1 clients. Neither client implements an in-app password reset completion
screen: it requests email and shows neutral confirmation; the email action handler
owns the new-password entry and error presentation. Its behavior under the proposed
policy still requires an authorized end-to-end check, not an inference from email
request success.

Safest rollout: retain the current server policy until the compatible client and
reset flow are accepted and available, or Ken explicitly accepts the older-client
registration impact. Before any separately approved change, capture the full current
console configuration. In Firebase Authentication > Settings > Password policy,
propose minimum **8**, maximum **4096**, uppercase/lowercase/numeric **required**,
non-alphanumeric **optional**, and retain enforcement. Keep forced password upgrade
on sign-in **off**; verify the console value explicitly because the read response
omitted it. [Firebase's password-policy guidance](https://firebase.google.com/docs/auth/ios/password-auth#recommended_set_a_password_policy)
warns that forcing upgrade can block existing users. Do not change providers or
other security settings as part of this rollout.

After approval, read back the policy and have the owner verify a pre-existing
six-character account can still sign in on V1 and V1.1, new registration rejects
noncompliant input and accepts compliant input, and the real reset link reports
requirements and completes successfully. Account creation, reset email, and password
entry each need the appropriate deliberate owner authorization; credentials and
links stay out of evidence. Any rollback to the captured policy is also a separately
approved security change, not an automatic response to a failing check.

Registration tests use injected operations and synthetic credentials, not live
account creation. The interaction suite covers navigation, credential isolation,
local validation, visibility/background masking, and large-text reachability.
Physical VoiceOver and password-manager/AutoFill checks remain necessary; UI
hierarchy assertions do not prove speech, focus, or password-manager integration.

Verification and remaining DW-005 acceptance limits are summarized in
[testing](../docs/testing.md#dw-005-development-evidence). Detailed execution
discussion belongs in [DW-005](https://github.com/KenWidemon/daily-whiskers/issues/54)
and [PR #69](https://github.com/KenWidemon/daily-whiskers/pull/69).

## Account and Privacy Readiness

See [account/privacy audit](../docs/account-privacy-readiness.md) for deletion
behavior, data inventory, and published privacy/support decisions. Guest-first
copy and dedicated reviewer preparation are complete; final-candidate checks
remain in the release checklist. Implementation is not release acceptance.

## Authentication Recovery

- Password reset uses Firebase's reset email flow. Confirmation is deliberately
  neutral whether the account exists or not; it does not prove email delivery.
- Sign-in, account creation, and reset share a request lock. Controls are disabled
  while a request is pending, and failures allow retry.
- Logout failures show an alert with Try Again and Cancel, retaining the daily screen.
- The debug test-account UI, credentials, and helper are excluded from Release builds.

Recovery unit tests use injected operations, not live Firebase or real email.
Before release, manually verify reset delivery to a controlled account (including
spam), login persistence after relaunch, and offline/retry behavior. A reset request
alone does not change the password; completing the emailed link does.

## Setup

V1.2 supports iPhone and iPad running iOS/iPadOS 26.2 or later. The deployment
target is defined in `project.yml`; testing on a newer OS does not qualify the
exact 26.2 minimum runtime. Earlier released builds retain their recorded support.

1. Install XcodeGen:
   - `brew install xcodegen`
2. Generate project:
   - `xcodegen generate`
3. Open project:
   - `open DailyWhiskers.xcodeproj`

## Firebase Config
1. Place Firebase plist at:
   - `DailyWhiskers/Resources/GoogleService-Info.plist`
2. Regenerate project after adding/moving plist:
   - `xcodegen generate`
3. In Firebase Console > Authentication > Sign-in method:
   - enable `Email/Password`
4. Build and run from Xcode.

The app currently depends on:
- `FirebaseCore`
- `FirebaseAuth`

## Test Account Behavior (Debug)
In Debug builds, "Use Test Account" is visible only when both launch environment
variables `DAILY_WHISKERS_TEST_EMAIL` and `DAILY_WHISKERS_TEST_PASSWORD` are set.
Configure them in a local, unshared Xcode scheme. Never save credentials in the
shared schemes, source files, documentation, or CI logs. Leave them unset for
normal development and automated UI checks.

The helper attempts sign-in first and can create the configured account when
Firebase reports it missing. Use only a controlled development account. The
helper and its environment lookup are excluded from Release builds.

Previously embedded credentials remain in Git history. Ken reported disabling
that legacy account in Firebase Console on September 13; the agent did not
independently verify disabled state or token behavior. Do not reuse that account.

## Release Readiness

The English App Store copy and screenshot storyboard are in the
[listing record](../docs/app-store-listing.md). Approved metadata and six final
screenshots are saved in App Store Connect. V1 build 1.0 (1) was uploaded and
submitted; use the release checklist for the latest owner-reported resubmission
and remaining approval gates.

See [release readiness](../docs/release-readiness.md) for configuration, archive
requirements and credential safeguards. Older archives are not the current RC.
`project.yml` prepares version `1.1`, build `3`. This does not change the frozen
V1 `1.0 (1)` artifact or establish a signed, uploaded, or accepted V1.1 candidate.
Recheck build-number availability before any separately approved upload.

## Content Pipeline
Primary content file:
- `DailyWhiskers/Resources/daily_whiskers_content.json`

Schema:
- top-level `cards` array of objects:
  - `id` (required, unique)
  - `archetype` (required)
  - `imageName` (required)
  - `quote` (required)
  - `vibe` (optional)

Load-time integrity checks:
- JSON decode success
- required fields non-empty
- duplicate `id` rejected
- `imageName` must resolve to `CardOriginals/<imageName>.png` through the shared
  `BundledCardArtwork` loader
- invalid cards are dropped with integrity logging
- if no valid cards remain, app uses a built-in fallback card

Image import details:
- See [content pipeline](../docs/content-pipeline.md).

## Optional Daily Reminder

Settings → Daily Reminder is device-local and available without an account.
It starts off, with an editable 9 a.m. suggestion. Only explicit enablement can
request alert permission; saving a time does not enable it. Save/Cancel edits the
time separately. Notifications use the evergreen title “Daily Whiskers” and body
“Your daily whisker of encouragement is ready.” There is no sound, badge, push,
server scheduling or foreground banner. Focus, Scheduled Summary and iOS settings
control actual presentation; this is not an exact-delivery alarm.

The scheduler queues date-specific, nonrepeating UTC targets for the current
Gregorian civil date plus the next thirteen labels in the current time zone.
Passed targets and wholly nonexistent dates are skipped without backfilling a
fifteenth date. Reopening extends this finite window; no background renewal is
assumed. Repeated times select the first occurrence. A missing wall time resolves
to the next valid instant on that same date, including half-hour/midnight gaps.
Queued requests retain their old zone until reopening. During unopened date-line
travel, two scheduling dates can fall on one experienced local date. Settings
discloses both finite coverage and this travel exception.

A serialized scheduler writes a versioned, checksummed Application Support journal
before notification side effects. Possibly-presented date/interval history survives
edits, disable/re-enable and zones. Empty Notification Center is not proof of
nondelivery. Interrupted add/cancel intents, elapsed targets and uncertain removals
retain reservations; suppression is preferred to replay. Known obsolete requests
are cancelled before any capacity check or addition. The app uses a conservative
32-pending-request budget, reserving space for unrelated requests; this is an app
policy, not an assertion about a modern iOS maximum.

For an acknowledged request observed pending with scheduling permission, removal
followed by two absent readbacks more than sixty seconds before its target permits replacing its future
reservation. This is operational removal evidence, not an atomic cancellation or
delivery barrier. Permission must still allow scheduling after removal. Missing
requests, interrupted intents/cancellations, unknown inventory or a closer deadline preserve uncertainty instead. Readback after each
add checks retention. Corrupt/missing initialized state fails closed without
resetting history. Persistent quarantine or invalid history directs the user to
Support and explicitly says reopening cannot repair it. A potentially temporary
storage/verification failure requires a complete app restart to recheck; the
current process cannot resume additions after uncertainty. Neither path resets
the ledger. Atomic file replacement, synchronization and readback do not
establish universal power-loss or backup-restoration guarantees.

Disabling saves OFF before asking iOS to remove this feature's pending and delivered
notifications, while keeping
the chosen time and eligibility history. OS permission revocation retains enabled
intent. An enabled, acknowledged request with an unchanged time/zone/absolute
target remains untouched while permission is denied. Empty or unavailable denied
inventories do not prove removal or authorize replacement. On reopening after
regrant, visible matching originals are kept without cancellation or re-addition.
Full trigger/content readback must match the expected nonrepeating UTC request;
identifier-only readback cannot confirm coverage. Unknown or conflicting owned
requests quarantine. Unavailable inventory confirms no coverage; an authorized
empty inventory suppresses missing dates rather than restoring requests.

OFF, time/zone edits, elapsed targets, observed clock reversal and existing possible
exposures still use conservative cancellation. Positive delivered-ID evidence
blocks a future pending copy even if Notification Center is later cleared. Legacy
v2 suspension flags may already have issued removal, so they retain conservative
cancellation rather than entering the untouched-original path. Missing dates can
remain suppressed through the original horizon; later unexposed dates refill on
reopening. No absent-ID restoration or exposure erasure is performed.

iOS may resume a retained reminder as soon as permission returns, including after
OFF while denied, before
the app reopens. Reopening checks and refills eligible coverage; it is not a gate
that guarantees no earlier alert. Disabled intent never automatically re-enables.
Observed clock safeguards do not establish universal exactly-once presentation or
rule out an unobserved forward-then-back clock excursion.
Retired request IDs retain target provenance indefinitely, so delayed reappearance
triggers conservative cancellation rather than unknown-ID quarantine. These records
are not delivery receipts and never erase existing exposures. Existing v1 journals
without the optional provenance fields remain readable and upgrade to v3 before
scheduling or writing new provenance. A previously quarantined
journal whose ID/target mappings were lost remains quarantined; this change cannot
reconstruct them or repair that device automatically. Verified quarantine accepts
and persists OFF intent and retries owned-notification cleanup without clearing the
recovery flag. Unreadable history or uncertain writes still fail closed. Older
v1/v2 binaries reject v3 journals and fail closed rather than dropping cleanup
verification state. Downgrading does not restore normal scheduling automatically.
Cleanup verification is separate from saved enablement, retired IDs and exposure
history. Missing/null cleanup state and v1/v2 journals are unverified, even with
no active entries, a false delivered-clear flag, or only retired/exposure records.
Fresh journals also begin unverified until authorized observations establish
cleanup; an empty denied inventory cannot establish a never-scheduled history.
Malformed state fails closed. Cancellation intent and possible failed-add cleanup
are saved before notification effects. Failed OFF persistence reports storage
failure, not a successfully saved OFF preference. The UI publishes the saved
intent after the serialized operation finishes; it does not update atomically
with the tap.

The cleanup warning survives refresh/restart and changes its OFF/ON wording with
current saved intent. It is cleared only after two available full pending and
delivered snapshots, bracketed by schedulable authorization before, between and
after. OFF requires no owned pending or delivered IDs. ON permits only
exact-matching active originals; cancelled/retired IDs still prevent verification.
An ON migration does not invent permission to clear old delivered notifications;
those can leave verification pending and defer new scheduling. Explicit OFF
retains delivered-cleanup intent until both snapshots confirm absence. Unknown
pending inventory or observed authorization loss cannot clear either flag.
The delivered callback has no error/unavailable result in the current protocol;
its returned inventory is an observation, not a guarantee of complete OS state.

Clearing both flags is one verified journal save. A failed/uncertain save blocks
new adds in that process. Error cleanup re-reads the durable marker before any
additional removal, since a clearing save may have committed before throwing.
Restart can accept that committed clear only because authorized verification
already preceded it. History and quarantines are never reset to remove a warning.
Authorization samples do not exclude an unseen deny/regrant between callbacks.
The warning does not prevent a regrant-before-reopen alert. Do not ask users to
regrant solely to finish cleanup. The owner accepted this disclosed pre-reopen
alert limitation for V1.3. Acceptance does not prevent the window or establish
physical nondelivery; regression tests do not prove either.

The journal can grow with scheduling/cancellation history; no unproven pruning rule
is used.
Denied permission never causes automatic prompts or blocks daily cards. A reminder
tap ignores old content dates and returns to current Today, dismissing navigation
and sheets without deleting saved cards or rerolling daily/bonus selections.

The focused tests use injected clocks, journals and notification clients. The
compile-only offline UI seam never accesses the system notification center.
See [reminder acceptance](../docs/testing.md#daily-reminder-acceptance) for the
separate integrated-device checks. The broader Settings shell remains outside this
feature's minimal entry/editor.

## Tests
- Repeatable acceptance checks and evidence limits: [testing](../docs/testing.md).
- Unit tests live in `DailyWhiskersTests/`.
- Current suite validates:
  - JSON decode path
  - deterministic daily selection
  - fallback behavior
  - rollover expectations
  - missing-image validation behavior
  - empty/all-invalid manifests, required fields, duplicate IDs, and normalization
  - bundled manifest and asset integrity, including the fallback image
  - foreground refresh state across month/year/leap-day boundaries and missed days
  - time-zone selection and daylight-saving transitions

Run the unit suite on an available dedicated simulator after configuring Firebase
and regenerating the project (CI uses the fake fixture described below):

```sh
xcodebuild test -project DailyWhiskers.xcodeproj \
  -scheme DailyWhiskers \
  -destination 'platform=iOS Simulator,id=YOUR_QA_SIMULATOR_ID' \
  -parallel-testing-enabled NO -onlyUsePackageVersionsFromResolvedFile
```

## Continuous Integration

The `iOS CI` workflow runs on every PR targeting `main`, `codex/develop`, or
`release/rc`, pushes to those branches, and manual dispatch. Its final **CI Gate**
checks the actual results of classification, documentation/policy checks, and the
unit/Release job, UI shard matrix and aggregate evidence. Only a successful
docs-only classification permits both app jobs to skip. The required check
name remains **CI Gate**; this change does not modify branch protection.
A failed, cancelled, timed-out, missing, or unexpectedly skipped prerequisite
cannot pass the gate. Workflow-level path filters are deliberately absent.
A whole-run cancellation or service outage can prevent the gate from executing;
required-check enforcement must leave that PR blocked, never treat it as a pass.

Documentation-only means changes exclusively to `docs/**/*.md`, `AGENTS.md`,
`DailyWhiskers/README.md`, `ci/screenshots/README.md`, or the PR template. Renames
consider both old and new paths. Empty, unknown, or unreadable comparisons take
the full path. Scripts, workflow/configuration files, dependency locks, source,
tests, and resources require app validation. Pushes/manual runs always validate
the app. Classification uses the PR base/head merge-base; validation checks out
GitHub's proposed merge commit.

The separate disposable selected-test workflow is diagnostic-only and cannot
satisfy CI Gate. Its managed-launch sequence, unchanged limits and evidence rules
are defined in the [testing guide](../docs/testing.md#disposable-selected-test-diagnostic).

### Documentation and policy checks

Every run checks Markdown formatting, repository-relative links and Markdown
heading anchors across tracked documentation. Tools parse Markdown without
executing embedded content or fetching external URLs. External URL availability
is outside this deterministic gate. Paths and symlinks cannot leave the checkout.
The formatting rules preserve existing prose conventions; this is not a rewrite
of the documentation. CI also lints workflows and tests classification, gate
results, and the link checker.

```sh
python3 -m unittest discover -s ci -p 'test_*.py' -v
npm ci --ignore-scripts --prefix ci/checks
npm test --prefix ci/checks
npm run check --prefix ci/checks
```

Node 24.12.0 and the documentation tool lockfile define the check environment.
`npm ci --ignore-scripts` does not execute dependency lifecycle scripts. Tool
updates must update the lockfile and pass the checks in the same PR.

### App validation and pinned inputs

Every app job uses the official `xcode-27` ARM64 **preview** runner, explicitly
selects `/Applications/Xcode_27.2.app/Contents/Developer`, and requires Xcode
**27.2 / 27B52**, simulator SDK **27.2**, and **iPhone 17 Pro / iOS 27.0 / 24A434**.
The [official image manifest](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
at image `20261104.0337.1` lists Xcode 27.2, but defaults to 27.1 and does not
list or promise a precreated iPhone 17 Pro. The workflow does not change global Xcode defaults, download
another runtime, or fall back to another installation/model/runtime. Runner image,
architecture, Swift/SDK versions and simulator provenance are logged. Hosted
images remain mutable; pinned inputs fail closed on drift, not byte-identical
signed artifacts. The preview label is narrowly allowed in `.github/actionlint.yaml`
because actionlint 1.7.12's built-in catalog predates it; other validation remains.

`ci/simulator.py` requires one available exact runtime identifier
`com.apple.CoreSimulator.SimRuntime.iOS-27-0`, version 27.0, build 24A434, ARM64
support and an explicit compatible iPhone 17 Pro device type. It reuses exactly
one matching available named device, rejects ambiguity, or creates one only when
none exists. Creation intent, baseline UUIDs, returned UUID/ownership and readback
are durable before testing. A timeout or unreadable creation result leaves
ownership uncertain, never permission to guess a UUID or delete by name.

Every app job runs bounded `always()` cleanup before collecting evidence. Only a
positively owned UUID absent from the baseline may be shut down/deleted; preexisting
devices are preserved. Cleanup shares a 45-second command deadline inside a
one-minute step and verifies absence after deletion. Missing, failed or uncertain
cleanup fails the job and manifest gate. Runtime/device snapshots, preparation and
cleanup status are uploaded with the other evidence. Local offline tests mock all
simctl operations; they do not prove hosted compatibility or cleanup behavior.

XcodeGen **2.46.0** is downloaded from its release and checked against a committed
SHA-256. Actions use Node 24 and full commit SHAs with release comments; actionlint **1.7.12**
is checksum-verified. When updating tools, verify upstream release identity,
change the version/hash together, and rerun both cold and warm validation.

CI copies `ci/firebase-test-config.plist` into the app resources before project
generation. This fake fixture initializes the hosted test app without live
Firebase access. PRs receive only `contents: read`, checkout does not persist
credentials, and no release secrets are used. App validation runs the Debug
unit suite, the required offline UI inventory, and an unsigned Release build for
`generic/platform=iOS Simulator`. Release compiles and packages simulator code;
it is not a signed archive, device build, distribution or physical acceptance.

The required offline UI inventory is `ci/ui-inventory.json`. Three independent
hosted jobs select whole classes from the interaction scheme:

| Shard | Required classes | Cases |
| --- | --- | --- |
| `cards` | `SavedCardsTests` | 7 |
| `settings` | `RegressionSmokeTests`, `StillnessModeTests` | 8 |
| `reminders` | `ReminderUITests`, `SavedCardsLoadStateTests` | 12 |

The inventory lists every method and explicitly identifies the existing optional
`AuthLayoutTests`, `BonusCardTests` and `DailyCardSharingTests` coverage. Source
changes must update this reviewed inventory: missing, duplicate, unknown and
unassigned classes/methods fail policy checks before Xcode runs. A new required
feature class must enter exactly one shard; it must not be made optional to get
a green gate. `ci/test-app.sh ui` requires `CI_PART=cards`, `settings` or `reminders`.
Each class retains serial XCTest execution and its existing compile flags,
launch fixtures, assertions and state waits. No test is retried or skipped.
The matrix uses `fail-fast: false` so one failing shard does not cancel the others.

The five smoke tests cover
guest daily content/relaunch, account tools open/dismiss, local reset and
registration validation/navigation, and repeated registration editing after Back,
Close and process relaunch, plus single-password Done submission to the rejecting
offline boundary. The Saved Cards tests cover save/relaunch/reopen/share,
remove/resave and confirmed clear, largest-text portrait/landscape reachability,
ordinary-phone full-card fit, and paired Today/Saved geometry and options.
Stillness checks use a fresh preference-domain fixture and verify the actual system
Reduce Motion value is off before motion-positive controls. They cover defaults,
live app-toggle stop/resume, persistence, local account navigation, foreground return
and largest-text settings layouts. All actual app/system combinations, live OS
preference propagation, VoiceOver and timeline/power profiling remain mandatory
manual checks.
The four load-state tests cover held/failed first reads, alert dismissal, in-place
Retry, retained rows after a later failed refresh, verified empty guidance, and
largest-text Retry reachability. A held Retry crosses app background/foreground,
receives an injected read cancellation, fails again, and then recovers without duplicates.
They seed a disposable SQLite file selected by
`DW_SAVED_LOAD_TEST_ID` (a UUID), requiring the offline compile/launch gate plus
`--ci-smoke-saved-load-fixture`. They never clear the ordinary collection.
These classes use accessible identifiers and
bounded state waits, without retries, credentials, email or live account changes.
The smoke and optional auth-layout Debug commands add `CI_SMOKE_TESTING`; with `DEBUG` and
`--ci-smoke`, this skips Firebase initialization/listeners, starts signed out, and
rejects every backend auth operation. The visible offline marker is asserted by
the tests. Ordinary Debug and Release builds exclude this code. The Release
check also rejects binaries containing the smoke seam's symbols/marker/argument.
The larger `AuthLayoutTests` suite remains separate and also requires the offline
marker before interaction, including now-valid single-password submissions.

Each stage records start, completion, exit code and duration before the next
stage. Unit and Release checks run independently after successful package
resolution. UI shards prepare and resolve on separate hosted runners/simulators.
A failure in one does not hide the other results. An always-run evidence
check rejects missing/unreadable result bundles and zero tests. Required unit and
UI smoke suites must report zero ordinary failures, skips and expected failures,
even when the aggregate result is `Passed`. Missing or invalid top-level count
fields fail evidence validation; they are not interpreted as zero. Summaries retain
the expected-failure count when rejecting a suite.
Summaries use `xcresulttool get test-results summary`, which includes both XCTest
and Swift Testing; they report test cases separately from per-device executions
including dynamic parameters. Console XCTest totals are not combined or used as
a substitute. Source head, tested checkout (including synthetic PR merge), event
SHA, Xcode/Swift/SDK, observed simulator/runtime, counts, stage outcomes/durations,
and artifact links identify the evidence. Raw failure details remain in the
result bundles/logs instead of copying potential account data into summaries.

Each shard additionally reads `xcresulttool get test-results tests` and requires
exactly its assigned method identities, each passed once, with matching summary
counts. `results.json` records the source and tested checkout SHAs, event SHA,
repository, run, attempt, inventory digest, toolchain and observed device/runtime.
Both collection and the final gate also bind each stage name, source/tested SHA,
run/attempt, job and shard to the current manifest; current outer metadata cannot
relabel stale stage evidence. The final gate downloads four small manifests (unit/Release plus all three UI
shards) and validates their contents independently of the matrix status. It
rejects absent, unreadable, duplicated, stale or incompatible evidence. Device
UUIDs may differ across runners; each observed test UUID must match its own prepared
device and verified cleanup record. Model, architecture, exact OS/build and
toolchain must match across jobs. Artifact names include source SHA, run, attempt and part; each UI bundle
also includes its shard name. Raw result bundles/logs remain separate artifacts.
A partial job rerun cannot reuse earlier-attempt manifests: rerun the complete
workflow for a new complete gate result.

Collection preserves part/run identity, the reviewed inventory, stage statuses,
toolchain, budget, cache and simulator records independently before pass validation.
An unreadable summary or UI tree cannot erase the remaining failure evidence.
Each missing/unreadable component has an explicit error; xcresult reader errors
retain the operation, exit code and at most 4096 characters of stderr, with a
truncation flag. Readers remain bounded to 45 seconds each. Missing counts,
observed device or executed identities stay unavailable rather than being filled
from the requested destination or inventory. Failed manifests remain failed, and
aggregation identifies the failing part instead of treating it as an absent shard.

Overall summaries run even on dependency failure and explain docs-only app skips.
For a docs-only PR, inspect the CI Gate summary for both source and tested merge
SHAs, the docs classification, and explicit not-applicable app counts, duration,
toolchain/device evidence and artifacts. A skipped app job alone does not prove
that this summary was published or establish an app test pass.
Interrupted stages and unavailable results never claim a pass. Original command
failures remain failures even if summary generation succeeds. Hard cancellation
or runner loss can prevent summaries/artifacts entirely; missing CI is not green.

### SwiftPM cache and lock enforcement

The committed `Package.resolved` must exist and remain byte-for-byte unchanged
after project generation, dependency resolution, and tests. Resolution/build
use `-onlyUsePackageVersionsFromResolvedFile` and
`-disableAutomaticPackageResolution`. Dependency upgrades require an intentional
lockfile change in the PR; a cache hit never substitutes for resolution or tests.

Only `build/SourcePackages` is cached. Keys include OS, architecture, Xcode build,
simulator SDK platform/version, lockfile hash, and a cache epoch. There are no
broad restore keys and no DerivedData products, credentials, or Firebase config
in the cache. The unit/Release job saves the cache only after its own validation succeeds;
UI shards restore it without competing writes. Cache availability does not
indicate that UI validation passed. GitHub scopes
PR caches to the PR merge ref, so untrusted PR runs cannot populate the base
branch's shared cache. Fork runs may have restore-only cache access; cache-save
denial is not validation failure and must never be worked around with broader
permissions. Manual runs use their selected branch's cache scope.

For a cold/warm comparison, dispatch the same commit twice with a fresh, identical
`cache_epoch` value. The first must report a miss; the second must report a hit.
Use the same runner/tool configuration and compare the job summaries for
resolution, build/test, and combined seconds. Record actual measurements and run
links in the issue/PR, not a promised speedup or a README execution journal.
Changing the epoch safely abandons an old cache without deleting evidence.

Immediately before restore, `ci/cache_window.py` verifies the existing budget's
source/run/attempt/job/shard identity, 2700-second duration and exported absolute
deadline. It never renews or rewrites the budget. From the remaining seconds it
subtracts **60 seconds** for ordinary runner transition/helper overhead, rounds
down to whole minutes and caps restore at **five minutes**. Fewer than one usable
minute skips only the cache optimization. For example, 120 seconds remaining
permits one minute; just under 120 skips; 360 permits five minutes. Missing,
malformed or stale budget data fails closed instead of enabling a fallback.

Both plan and report run through the shared deadline wrapper. Report requires a
successful plan, so preparation timeout cannot add an unconditional cache-report
step afterward. The restore action additionally requires an explicit enabled flag
and an allowlisted timeout of 1–5; missing/zero/unknown outputs cannot start it.
A skipped plan exports a finite inert one-minute timeout, never zero/unlimited.
Cache save requires a successfully completed restore action and validated tests.

`build/cache-status.json`, its wrapper logs/status and the aggregate manifest
retain the selected/skipped window and observed action outputs. Collection and
aggregation validate that provenance against the current source/tested checkout,
run/attempt/job/shard and the original budget file. All wrapped execution stages,
including cache plan/report, must carry that same deadline; cleanup is outside it.
A self-consistent cache window cannot substitute a renewed deadline. Summaries distinguish `exact_hit`, `cold_miss`,
`partial_restore`, `skipped_budget` and unavailable/failed evidence. A valid skip
does not fail app validation, but skipped/partial/failed restore never qualifies
as either a cold or warm control. A report after the deadline is rejected.

Each app job keeps a 60-minute hard timeout. After checkout, each unit/Release
job and UI shard initializes its own shared **45-minute execution budget** once.
Preparation, cache restore, dependency resolution and that job's validation stages
share the same absolute deadline; subsequent stages fail without starting once it
expires. The 15-minute reserve covers checkout (three minutes), up to 60 seconds
of graceful process-group shutdown plus bounded forced termination, result reading
(45 seconds per reader; two-minute step), cache save (one minute in unit/Release),
owned-device cleanup (one-minute step, 45-second shared command deadline), raw
artifact upload (five minutes), manifest upload (one minute), and summary
publication (one minute). Accounting must follow the actual conditional paths:
success requires no watchdog grace, so the reserve step caps total 840 seconds
for unit/Release or 780 seconds for UI. A watchdog failure allows 65 seconds for
shutdown/reaping but skips the success-only cache save, totaling 845 seconds for
either job. This leaves at least 55 seconds of nominal runner overhead within the
900-second reserve; cleanup's shorter command deadline is additional margin.
The cache window removes the old unconditional five-minute restore overrun under
its stated 60-second transition/helper-overhead assumption. GitHub's action timeout
is relative to action execution, not the shared wall-clock deadline: arbitrary
runner suspension or scheduling delay can exceed that allowance. The following
wrapped stage rejects an expired budget, but cannot reclaim lost upload time.
Verify actual hosted timing and failure-path uploads; the accounting is not a
guarantee during runner stalls, clock changes, service cancellation or runner loss.

This retains the shard job ceilings instead of carrying the serial 90-minute
ceiling into every parallel job. The 45-minute budget is provisional and must be
checked on the combined pinned hosted candidate; earlier shard results do not
qualify this integration. This is a reserve under normal runner operation, not a
guarantee during runner loss or service cancellation. `build/job-budget.json` and
each stage status retain budget/deadline and source/run/job identity. Every job
sets `CI_SHARD_ID` equal to its evidence part (`unit-release`, `cards`, `settings`
or `reminders`), so parallel jobs never share a deadline or evidence directory.

A deadline produces `timed_out` / wrapper exit 124 even if the terminated command
returns zero; its original command exit remains recorded. SIGTERM/SIGINT produce
`interrupted` with a nonzero wrapper exit. Logs stream and persist during execution.
The runner sends SIGTERM to its command process group, allows result finalization,
and escalates to SIGKILL after 60 seconds. A denied cleanup signal preserves the
observed command exit and records cleanup as unverified; it cannot turn the
timeout into a pass. Missing, partial or unreadable bundles
remain failures. Evidence collection and upload run after ordinary stage failures
or budget expiration. A missing/malformed hosted deadline fails closed.

### UI execution limits

The required offline UI invocation enables XCTest timeouts with both the default
and maximum per-test execution allowance set to **720 seconds**. The maximum
prevents an individual test's preferred allowance from escaping the limit. These
are execution limits, separate from assertion waits and meaningful synchronization;
no retry, skip selector, additional tap or assertion-wait change is introduced.
See Apple's [execution allowance contract](https://developer.apple.com/documentation/xctest/xctestcase/executiontimeallowance)
for minute rounding and the command-line maximum.
No exceptions are currently configured. Xcode may spend additional time gathering
timeout diagnostics, so this is not an exact wall-clock kill; the job watchdog
bounds the overall process. Swift Testing/unit execution is bounded by the shared
job deadline; this UI XCTest setting does not claim per-test Swift Testing limits.

The starting allowance retains its historical calibration from two hosted iPhone 17 Pro / iOS 26.4.1,
Xcode 26.6 / 17F113 / simulator SDK 26.5 samples:
[run 42527479814](https://github.com/KenWidemon/daily-whiskers/actions/runs/42527479814)
(source `8ba6bd88df3c385e354eb3efe76d67d55f587cce`, tested merge
`9d372399f46bdda05cad3b974f593b4c7f29d570`) and
[run 42533295957](https://github.com/KenWidemon/daily-whiskers/actions/runs/42533295957)
(source `b830d77e44ad397a038f6f09e43239cfd7dd72ab`, tested merge
`f5dfc1a9716db3ba5bce0872c66f440fc1229d60`). Application and test source are
identical between these heads; only the workflow budget and README differ.
The slowest completed valid case, Saved Cards adaptive-window coverage, took
356.726 and 296.253 seconds. Paired largest-text geometry took 295.780 and
238.857 seconds; registration editing/relaunch took 250.580 and 218.411 seconds.
720 seconds gives roughly twice the observed maximum, rounded to whole minutes.

This is a provisional bound, not a statistical performance guarantee: only two
runs, one device/toolchain and a limited runner-variability sample. The earlier
run was cancelled by its job timeout with an incomplete UI bundle; its 26
completed console timings are timing samples only, not passing suite evidence.
The later complete bundle reports 31 UI cases with three ordinary assertion
failures; failure durations are not used as normal completion thresholds. The
comparison includes four Mischievous Cards cases from the separate draft #139,
without adding that feature or changing trunk's required test selection. Retain
that distinction when recalibrating after sharding, toolchain, test-inventory or
runner changes. Validate normal slow cases and a deliberate over-budget probe
with exact source/run/toolchain identities before treating a new limit as accepted.
The Xcode 27.2 / iOS 27.0 migration invalidates earlier runtime and timing
acceptance; the retained 720-second limit and 2700-second job budget are
provisional on this stack. Fresh cold/warm controls, normal slow cases and isolated
timeout proofs are required. A toolchain update is not evidence that the earlier
Saved Cards `app.terminate()` teardown failure was caused by, or fixed by, a
configured timeout. Preserve each failure's original source and environment.

The deadline wrapper is exercised with real silent, SIGTERM-ignoring and descendant
processes in `ci/test_time_limits.py`. To verify XCTest behavior separately, use an
isolated disposable test target with a slow valid test below its chosen allowance
and a hung test above it; require a failing command, a readable failing result
bundle, and the original timeout diagnostic. Keep the deliberate failure out of
required product inventory and never merge it or treat a failed proof as green.

Concurrency cancels superseded runs for the same PR/ref. Logs, timing summaries,
and `.xcresult` bundles are uploaded when available, including failure paths,
with 30-day retention. This gives investigation and acceptance reviews more time
than seven days without the storage use of 90 days. The policy applies only to
new artifacts uploaded by a revision with this setting; it does not extend or
restore existing artifacts. After an authorized validation, verify the actual
artifact expiry and source/tested SHA, run and attempt before relying on that
window. Preserve still-needed evidence separately before its recorded expiry.
Repository or organization limits can cap effective retention. Hard termination
can prevent artifact upload; missing artifacts are not proof of success.
The separate manual release-policy rehearsal retains its synthetic report for
seven days, as documented in the [distribution record](../docs/distribution-readiness.md).

### Gate verification and rollout

Before requiring CI Gate, exercise docs-only, app-only, mixed, and workflow-only
PR changes, plus broken links/tests, lock enforcement, timeout, cancellation,
unknown paths, and unexpected skips. Use disposable proof branches if the new
workflow is not yet on a target branch; clearly distinguish that evidence from
actual target-branch enforcement. Do not merge deliberate failures. Reruns and
manual dispatch are useful diagnostics but do not replace real PR-event proof.

Ruleset configuration and recovery are governed by the
[branching strategy](../docs/branching-strategy.md#ci-and-protection). The workflow
alone does not protect branches. A passing workflow PR does not complete ruleset
rollout or authorize any release.

## Optional Interaction Tests

Select the `DailyWhiskersInteraction` scheme to run the UI checks on a dedicated,
signed-out simulator. They first verify guest entry and open Settings > Sign In.
They exercise optional-auth dismissal/relaunch, keyboard navigation and landscape form
scrolling at default and largest accessibility text sizes using empty fields,
plus repeated local validation-error visibility. The latter does not verify
VoiceOver speech or accessibility focus; those require physical acceptance.
Show the software keyboard in Simulator (I/O > Keyboard > Toggle Software
Keyboard). Tests require an on-screen, tappable keyboard key and fail clearly
when only an offscreen keyboard accessibility tree is available.
The auth-layout suite requires the offline marker before interacting. Synthetic
valid registration input reaches the rejecting offline boundary; no account is
created and no live authentication operation is permitted.

```sh
xcodebuild test -project DailyWhiskers.xcodeproj \
  -scheme DailyWhiskersInteraction -configuration Debug \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING' \
  -only-testing:DailyWhiskersUITests/AuthLayoutTests \
  CODE_SIGNING_ALLOWED=NO \
  -destination 'platform=iOS Simulator,id=YOUR_QA_SIMULATOR_ID' \
  -parallel-testing-enabled NO -onlyUsePackageVersionsFromResolvedFile
```

Use the fake `ci/firebase-test-config.plist` copied to the app resource location,
as in CI; this command builds an unsigned simulator app.
The existing `DailyWhiskers` unit-test scheme is unchanged. CI selects the
offline smoke, Saved Cards and Stillness Mode classes; the broader UI suite restores portrait orientation and passes text size as a launch argument,
rather than changing the simulator's persistent accessibility preference.

Historical baseline: the three keyboard/scrolling UI checks passed on iPad Air
11-inch (M4). The Pro Max largest-text landscape simulator failure remains
unresolved and was explicitly deferred for V1 after an owner-reported physical
scrolling pass. Keep that test and its assertions unchanged. The new validation
check is tracked separately;
see [testing](../docs/testing.md). This optional scheme
is not yet a fully green phone acceptance gate.

## Public Privacy and Support

- [Privacy policy](https://kenwidemon.github.io/daily-whiskers-site/privacy/)
- [Support](https://kenwidemon.github.io/daily-whiskers-site/support/)
- Contact: dailywhiskers.support@gmail.com. Operator: Kenneth Widemon.

Both destinations are accessible from optional sign-in and from Settings for
guests and signed-in users. Public site source is maintained separately in
`KenWidemon/daily-whiskers-site` and deployed through GitHub Pages.

## Branch / PR Workflow
Canonical remaining release steps and owner decisions:
[V1 release checklist](../docs/release-checklist.md). Keep its item numbers and
statuses updated as work proceeds; skipped items are not automatically waived.

Local archive/export steps and Apple account handoff:
[Distribution readiness](../docs/distribution-readiness.md).

Performance risks and scoped evidence: [testing](../docs/testing.md#v1-deferrals-and-performance-evidence).

Branch roles:
- `main`: stable release branch.
- `codex/develop`: development trunk for approved work, including work for later releases.
- `release/rc`: long-lived pre-release testing branch, initially created from
  `main`. It receives approved development snapshots through promotion PRs.
- `codex/<task>`: one task branch per roadmap item, created from `codex/develop`
  (for example, `codex/ci-baseline`).
- `codex/rc-<fix>`: release-fix branch created from `release/rc`, targeting RC
  first; bring every accepted fix back into the development trunk through a PR.

Expected flow per item:
1. Create a `codex/<task>` branch from the updated `codex/develop` branch.
2. Implement and verify one item only.
3. Get Ken's sign-off.
4. Commit, push, and open a PR into `codex/develop`.
5. Merge the approved PR before starting the next item.
6. When release scope is approved, promote `codex/develop` into `release/rc`
   through a PR. Freeze the candidate; do not automatically pull in later trunk work.
7. Test, archive, and validate the RC commit; record its tag, version/build, and
   artifact provenance. Any candidate change requires renewed relevant validation.
8. Promote the accepted `release/rc` into `main` through a release PR. Use merge
   commits for promotions between long-lived branches to preserve ancestry.
9. Keep `release/rc` and `codex/develop` synchronized with released fixes through
   PRs. App Store upload, review submission, and manual release remain separately
   authorized actions.

See [branching strategy](../docs/branching-strategy.md) for promotion, freeze,
fix propagation, candidate identity, and branch-protection expectations.
