# App Store Listing

Status: name/subtitle, tone, categories, locale, and screenshot direction approved
by the owner September 12, 2026. Prepared against merged revision `00d720d`.
English (U.S.) is verified as the existing primary language and listing locale.
Approved metadata is saved and six screenshots are uploaded to the version 1.0
draft in App Store Connect. No build upload or App Review submission occurred;
physical-device acceptance remains pending.

## Recommended Positioning

A small daily ritual for people who enjoy cats, imaginative artwork, and a few
quiet words. Lead with the card, not authentication or technical implementation.
Describe the images as artwork, not real cat photographs. Keep the tone warm
and restrained rather than promising self-improvement or therapeutic results.

## Listing Fields

The fenced blocks below contain the proposed customer-facing text only.

### Name

```text
Daily Whiskers
```

### Subtitle

```text
Cat art & a moment of calm
```

### Promotional Text

```text
A small paws for your day: whimsical cat artwork, a thoughtful quote, and a little wonder. Open Daily Whiskers for the card selected for today.
```

### Description

```text
A calm cat moment, once per day.

Daily Whiskers pairs imaginative cat artwork with a short, thoughtful quote. Open the app, spend a moment with today's card, and carry a few quiet words into the rest of your day.

ONE CARD FOR TODAY
Enjoy a card selected for your local date from a rotating collection of 31 illustrated cats and their accompanying quotes. Your card stays the same throughout the day. Return to the app after the day changes to see the next selection. Cards repeat as the collection rotates.

A LITTLE WONDER
Meet cats among spellbooks, forest lanterns, celestial skies, and cozy corners. Six visual themes bring their own colors and atmosphere to the daily card, with a short vibe tag to accompany the quote.

ROOM TO PAWS
No endless feed. No streak to maintain. Just artwork and a few words, presented in a simple, focused view.

GETTING STARTED
An email and password account is required. Create an account or sign in to view your card. Internet access is needed for account actions; artwork and quotes are included with the app. Password recovery is available on the sign-in screen, and you can delete your account from Settings.

A small ritual, with whiskers.
```

### Keywords

```text
quotes,kittens,cozy,fantasy,inspiration,reflection,ritual,celestial,whimsical
```

These are relevance-based suggestions, not measured search-volume or ranking
claims. They avoid repeating the proposed name/subtitle terms and omit competitor
names, prices, and unsupported features.

### Category

- Approved primary: **Entertainment**. The core experience is viewing themed art
  and quotes for enjoyment, rather than managing health or creating artwork.
- Approved secondary: **Lifestyle**, for the daily ritual/general-interest focus.
- Both categories are saved in App Store Connect. These choices are based on
  [Apple's category descriptions](https://developer.apple.com/app-store/categories/),
  not a guarantee of review acceptance. Do not select Health & Fitness or Kids
  solely because the presentation is calm or the cats are appealing.

### Initial Release Notes

For a launch announcement or release record, not a first-version App Store field:

```text
Meet Daily Whiskers: a calm cat moment, once per day. Our first release brings together 31 illustrated cat cards, thoughtful quotes, six visual themes, and a simple daily ritual.
```

Apple's What's New field is unavailable for the first app version. Keep this
copy for another appropriate use; do not describe V1 as an update with bug fixes.
See [platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).

## Screenshot Storyboard

Captions are drafted; six raw simulator previews were captured September 12,
2026. Dani approved all three cards and their order, as confirmed by Ken.
Ken approved all six final captioned compositions for iPhone and iPad.
All six are uploaded to the version 1.0 draft, not submitted for App Review.
Use actual release-candidate UI, keep the cat and quote legible, and avoid badges,
controls, galleries, or features that do not exist in the app.

| Order | Caption | Actual screen to capture | Purpose |
| --- | --- | --- | --- |
| 1 | A calm cat moment, once per day. | Signed-in daily card with the image, quote, and vibe visible | Show the complete core experience first |
| 2 | A little wonder in your day. | A different daily card with a contrasting theme | Show artwork variety without implying a browseable gallery |
| 3 | A few words to paws with. | A card with a short, readable quote and vibe tag | Emphasize the reflective tone |
| 4, optional | Your daily ritual starts here. | Release sign-in screen, empty fields, no debug account button | Make account entry visible without leading with a login form |

Capture iPhone and iPad layouts separately; do not stretch a phone image into
an iPad screenshot. The current app has no manual card picker. Capturing alternate
cards needs separate real dates or a separately approved capture-only process
that preserves the actual shipping layout; do not alter the phone clock or
silently reintroduce the removed profiling harness. Never display real account
credentials or imply that artwork changes every time the app is opened.

Export dimensions and opacity have been checked, and final compositions are
approved. Release-candidate acceptance remains open. Apple asks
screenshots to show the actual app experience; see
[creating your product page](https://developer.apple.com/app-store/product-page/).

### Preview Round: September 12, 2026

- Dani-approved order (confirmed by Ken): `celestial_constellation_watcher`, `forest_lantern_bearer`,
  `cozy_fireplace_sage`, paired with captions 1-3 above.
- Each card was independently captured on iPhone 17 Pro Max (1320 x 2868) and
  iPad Pro 13-inch M5 (2064 x 2752), both running simulator OS 26.5.
- The owner authorized the isolated capture setup. Eleven production Swift
  sources were copied unchanged, with a separate app entry point and offline
  router. No Firebase configuration, credentials, live account, device clock,
  shipping code, or shipping manifest was changed.
- The temporary bundle contains one unchanged production card per capture;
  this does not depict a card picker or imply multiple cards per day. It is
  visual evidence only, not a signed-in authentication or physical acceptance test.
- All six previews were inspected for visible artwork, complete quote/vibe,
  clipping, and private data. Captures retain native layouts, including the iPad
  window resize affordance. No UI retouching or caption overlays were applied.
- Local, Git-ignored originals and review sheet: `build/screenshots/2026-09-12/`.
  Per-card provenance records the source revision/hashes and original manifest
  hash. Keep these files until final exports are approved.
- Raw PNGs contain an alpha channel and are retained as originals, not uploads.
  Opaque captioned exports are available separately as described below.
  Card selection and order are approved; this is not upload approval.
- Reproduction instructions: [screenshot tooling](../ci/screenshots/README.md).

### Captioned Export Round

- Six compositions pair the approved captions with Dani's approved cards/order.
  Baskerville headlines and soft theme-tinted cream backgrounds sit outside the
  uniformly scaled native screenshots. No screenshot cropping or UI retouching.
- Three iPhone PNGs are 1320 x 2868; three iPad PNGs are 2064 x 2752. All six
  were decoded and verified as opaque 8-bit RGB, rendered in sRGB. These match
  [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
- Automated checks verified input/output hashes, caption bounds, PNG dimensions,
  and absence of alpha. Raw captures, recorded Swift sources, and the original
  manifest still match capture-time hashes. This is baseline parity, not approval
  of the eventual shipping release candidate.
- The six compositions were reviewed on contact sheets, with a full-size iPad
  spot check. Captions, artwork, quote, and vibe remain visible; smaller review
  sheets are not upload assets.
- Local exports: `build/screenshots/2026-09-12/compositions/`. The package
  `daily-whiskers-en-US-screenshots.zip` contains only the six full-size PNGs.
  Contact sheets, review notes, and `export-index.json` stay alongside the package.
- Ken approved both final composition sets, covering all six exported PNGs.
  Dani's earlier approval covered the card choices and order.
- Static comparison against the existing September 9 `1.0 (1)` archive/IPA passed;
  see the candidate comparison below. Ken subsequently authorized the screenshot
  upload, now complete. Physical acceptance remains open. No app source changes,
  simulator launches, or App Review submission were needed.

### Candidate Comparison

- Static comparison passed September 12 against the existing signed archive and
  exported IPA, not a newly built or newly accepted release candidate.
- Eleven captured production Swift files match the distribution-preparation
  revision `e3d8575` and current source. Git shows no subsequent shipping
  source/assets/project changes between that revision and capture revision
  `00d720d`.
- All 31 compiled card asset records match across the archive, exported IPA, and
  capture app. The archive/IPA `Assets.car` files are byte-identical; the full
  packaged daily manifest matches current source and capture provenance.
- The IPA remains `com.example.kenwidemon.dailywhiskers`, version `1.0 (1)`,
  minimum iOS 17. Its executable UUID matches the archive dSYM. Strict/deep code
  signature verification passed using macOS trust services outside the sandbox.
- Packaged Firebase configuration matches the local real config, not the CI
  fixture. Targeted capture/debug markers are absent from the IPA executable.
  The six approved composition hashes remain unchanged.
- Local evidence: `build/screenshots/2026-09-12/candidate-comparison.json`, including
  the candidate IPA hash. Temporary IPA extraction was removed after inspection.
- This does not establish device visual parity, fresh server validation, or
  current App Store Connect build availability. Recheck if the shipping UI,
  content, rendering configuration, or candidate changes. Physical acceptance
  remains open; no metadata, screenshot, or build upload was performed.

## App Store Connect Entry

Ken authorized saving the approved listing fields and uploading the six approved
screenshots to the existing record `6809050612`. This does not authorize a build
upload, App Review submission, or unapproved pricing, age-rating, or legal answers.

After Ken completed Apple Account sign-in, the following were saved and verified
through the authenticated UI on September 12, 2026:

- App name `Daily Whiskers`, subtitle `Cat art & a moment of calm`, primary
  Entertainment category, and secondary Lifestyle category. Reload confirmed
  these values persisted. Existing English (U.S.) primary language was preserved.
- Approved promotional text, description, keywords, and support URL. These
  persisted after navigation back to the version page.
- Approved privacy-policy URL, verified after reload. No privacy questionnaire
  answers were entered or published; the page still shows `Get Started`.
- Three 6.9-inch iPhone screenshots and three 13-inch iPad screenshots, each in
  Celestial, Forest, Cozy order. The default 6.5-inch iPhone slot uses the 6.9-inch
  set. Apple's initial multi-file upload reordered two images; only those newly
  uploaded files were replaced sequentially, and the corrected order was verified.
- The app remains `Prepare for Submission`. No build was selected or uploaded,
  and `Add for Review` was not used. Contact sheets and ZIP files were not uploaded.

During the initial listing entry, copyright, content-rights declarations, age ratings, privacy disclosures, reviewer
credentials/contact information, pricing/availability, and legal/regulatory setup
were not filled in. The existing automatic-release selection was left unchanged.
Copyright and content rights were subsequently completed as recorded below.
Privacy disclosures were subsequently published and age ratings saved as recorded
below. Reviewer fields remain incomplete.

Local upload record: `build/screenshots/2026-09-12/app-store-connect-entry.json`.
Earlier approval records describe their scope at that time; the subsequent
metadata/screenshot-only authorization did not authorize build upload or review.

### Content Rights and Copyright

- Ken confirmed the copyright line `2026 Kenneth Widemon` and identified ChatGPT
  as the source of the cat artwork and quotes. He confirmed that third-party
  photos, artwork, and copied quotations were not used as inputs.
- The page unexpectedly showed a third-party-content `Yes` answer before this
  change. Ken said he had not selected it intentionally. No cause was inferred.
- Based on Ken's provenance confirmation, the answer was changed to `No, it does
  not contain, show, or access third-party content`, saved, and verified after
  reloading App Information.
- The confirmed copyright line was saved on version 1.0 and verified in the
  refreshed page. This completes these two metadata fields, not an independent
  legal determination of copyrightability or a third-party-rights audit.
- No changes were made to age ratings, privacy disclosures, reviewer access,
  pricing, release behavior, or build/review submission in this pass.

### Privacy Disclosure Review (September 12, 2026)

Ken approved entry and publication of these answers. All three were subsequently
saved and published in App Store Connect after Ken accepted the final legal
confirmation at action time:

| Data type | Purpose | Linked to user | Used for tracking |
| --- | --- | --- | --- |
| Email Address | App Functionality | Yes | No |
| User ID | App Functionality | Yes | No |
| Other Diagnostic Data | Analytics | No | No |

- Initial data-collection answer: `Yes, we collect data from this app`.
- Rechecked the actual September 9 archive's app and dependency privacy
  manifests, rather than relying only on the app source manifest. FirebaseAuth
  declares unlinked Other Diagnostic Data for Analytics and linked User ID for
  App Functionality. The app adds linked Email Address for App Functionality.
- The remaining bundled manifests declare no additional collected-data types.
  No app-level analytics, crash reporting, advertising, phone authentication, or
  profile-name collection was found in the current app source/configuration.
- SDK diagnostics are not an added Google Analytics integration. Bundled card
  images and on-device daily selection are not user photo or activity uploads.
- Basis: the owner-confirmed email/password-only scope, packaged FirebaseAuth
  11.15.0 manifests, [Firebase's disclosure guidance](https://firebase.google.com/docs/ios/app-store-data-collection),
  and [Apple's definitions](https://developer.apple.com/app-store/app-privacy-details/).
  Firebase console/server integrations were not independently audited.
- Saved all three categories, purposes, linkage, and no-tracking answers. The
  product-page preview shows Contact Info and Identifiers linked to the user,
  with Diagnostics not linked.
- Ken explicitly accepted Apple's final agreement about accuracy, compliance,
  and prompt updates when practices change. Confirmed Publish, then verified the
  status `Published a few seconds ago by Kenneth Widemon` in the authenticated UI.
  The published preview retains the approved data categories and purposes.
- The previously saved policy URL remains present. A public-policy fetch through
  the web tool failed, so availability was not reverified here.
- Age ratings, build upload, and review submission remain separate steps.

### Age Rating Saved (September 12, 2026)

Reviewed the current Swift app features, all 31 quotes, and contact sheets of all
31 bundled illustrations. Ken approved the calculated 9+ rating, no higher-age
override, and no Made for Kids enrollment. Saved the questionnaire and verified
the resulting App Age Ratings section in the authenticated UI.

| Questionnaire category | Saved answers |
| --- | --- |
| In-app controls | No parental controls or age assurance |
| Capabilities | No unrestricted web access, UGC, social media, under-13 social-media mechanism, messaging/chat, or advertising |
| Mature themes | None for profanity, horror/fear, and alcohol/tobacco/drug use or references |
| Medical or wellness | No medical/treatment information; Yes for health/wellness topics |
| Sexuality or nudity | None for all three descriptors |
| Violence | None for all violence descriptors; Infrequent guns or other weapons |
| Chance-based activities | No gambling or loot boxes; None for simulated gambling or contests |

- Self-care/wellness reflects the rest/calm encouragement in the quotes, not
  diagnoses, treatment, or medical claims.
- `forest_elven_scout` depicts a bow and quiver of arrows. This supports
  infrequent weapons even though there is no depicted combat or injury.
- The policy/support links do not provide unrestricted browsing within the app.
  Bundled developer-provided artwork is not user-generated content functionality.
- Saved audience selection: `Not Applicable`, not `Made for Kids`, with no
  higher-age override and no suitability URL.
- Apple displays `9+` in 172 countries or regions, `12+` for Vietnam and Brazil,
  and `All` for Korea. Earlier-than-26 operating systems show a global `4+` with
  regional exceptions. No RCN was entered and no build/review was submitted.
- Definitions checked against [Apple's age-rating reference](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions).
- The underlying App Information page showed `Set Up Content Rights Information`
  despite the earlier saved/read-back record. This discrepancy was not changed
  during the age-rating draft. The subsequent recheck below resolved it.

### Reviewer and Distribution Setup Check (September 12, 2026)

- Reopened Content Rights: neither answer was selected. Restored the previously
  owner-approved No answer, clicked Done, then saved the parent App Information
  page. Waited for Saving to finish and reloaded; the No declaration persisted.
  No cause is inferred for the earlier discrepancy.
- App Review Information has sign-in required checked, with username, password,
  contact fields, and notes blank. Need a working dedicated reviewer account,
  owner-confirmed contact details, and a phone number. Password should be entered
  directly in App Store Connect, not chat or repository documentation.
- Pricing shows Add Pricing and availability shows Set Up Availability: neither
  is configured. Public distribution is selected; the existing tax category is
  App Store software. School Manager volume discount is checked by default.
- Apple silicon Mac and Vision Pro availability are checked. The page currently
  reports version 1.0 incompatible with Vision Pro. Do not confuse the checkbox
  with verified compatibility or shipping support.
- Automatic release after review remains selected. Proposed, pending approval:
  iPhone/iPad-only availability and manual release. Price and launch territories
  require owner direction; no distribution settings were changed in this check.
- DSA/account agreements and other regional requirements remain unresolved.
  No build upload, review submission, or app release was performed.

### Launch Settings and Contact Saved (September 13, 2026)

Following owner approval, configured and verified:

- Free launch price: United States base price `$0.00`, read from Current Price.
- United States only: Availability shows one country, United States, with
  `Available on App Release`; other territories are not available. Automatic
  inclusion of future App Store territories was left unchecked.
- Apple silicon Mac and Vision Pro availability disabled, verified after the
  subsequent sign-in. Public distribution remains selected.
- Version 1.0 uses `Manually release this version`, verified in a fresh tab.
- Review contact: Kenneth Widemon and dailywhiskers.support@gmail.com. The
  initial save reported a required phone number. Ken subsequently entered his
  phone directly in App Store Connect; visual inspection confirmed the complete
  contact fields, and Save was disabled. The phone value is not stored here.
- Dedicated reviewer username/password remain blank and explicitly deferred by
  Ken. Review notes remain a local draft until the final account is ready.
- No build upload, review submission, or release occurred. Account agreements,
  physical acceptance, and other outstanding release checks remain separate.

Prepared review notes (not yet entered; verify the final candidate and reviewer
account before submission):

```text
Daily Whiskers displays one illustrated cat card and quote for the current local
day. Sign in using the dedicated review account supplied in Sign-In Information.
An internet connection is required for authentication. Artwork and quotes are
bundled with the app; there are 31 cards and six visual themes. Selection is based
on the local calendar date, and the app refreshes on foreground if the day changed.
There is no card picker, purchase, subscription, advertising, or user content feed.

The settings menu contains Sign Out, Delete Account, Privacy Policy, and Support.
Account deletion requires password reauthentication and permanently removes the
Firebase authentication account. A reviewer-created account can be used to test
deletion without removing the supplied review account.
```

## Existing Public Details

- Operator: Kenneth Widemon.
- Public contact: dailywhiskers.support@gmail.com.
- [Support URL](https://kenwidemon.github.io/daily-whiskers-site/support/).
- [Privacy policy URL](https://kenwidemon.github.io/daily-whiskers-site/privacy/).
- Existing App Store Connect app ID: `6809050612`.
- Existing bundle ID: `com.example.kenwidemon.dailywhiskers`.

Operator/contact/URLs were previously approved. Support and privacy URLs are now
saved in App Store Connect; destination-site availability was not rechecked in
this entry pass. Ken subsequently confirmed the copyright line and content
provenance; the resulting entries are recorded above. The operator name alone
was not treated as proof of ownership of every image or quote.

## Copy Validation

Field limits checked against Apple's references on September 12, 2026: name and
subtitle at most 30 characters each; promotional text at most 170 characters;
description at most 4,000 characters; keywords at most 100 bytes. Draft fields
use ASCII, so their character and UTF-8 byte counts agree. See
[app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
and [platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).

Validated draft counts (excluding code fences and their boundary newlines):

| Field | Used | Limit |
| --- | --- | --- |
| Name | 14 characters | 30 |
| Subtitle | 26 characters | 30 |
| Promotional text | 143 characters | 170 |
| Description | 1,181 characters | 4,000 |
| Keywords | 77 UTF-8 bytes | 100 |

The copy reflects the current 31-card manifest, six archetypes, date-based
selection, foreground refresh, and email/password account flow. It does not
claim guest access, reminders, streaks, favorites, sharing, browsing, personalized
recommendations, newly published art each day, universal offline access,
accessibility certification, or an absence of all SDK data collection.

## Approval and Next Steps

- Owner approved September 12, 2026: name/subtitle, overall tone,
  Entertainment/Lifestyle categories, English (U.S.) locale, and screenshot
  direction. This approval does not authorize submission or distribution.
- Mandatory login is disclosed honestly. The separate guest-access decision
  remains deferred; revisit this copy if that decision changes.
- Pricing, availability, reviewer access,
  and distribution are separate tasks. No values were invented or submitted.
- Approved listing entry, screenshot uploads, and owner-confirmed content
  rights/copyright entries, privacy publication, and age ratings are complete.
  The content-rights discrepancy was resolved by re-entry and reload verification.
  Finish reviewer access and distribution decisions in separately scoped steps.
  Physical acceptance and outstanding release checks remain open.
