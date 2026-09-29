# App Store Listing

Approved V1 English (U.S.) customer-facing copy and metadata. Ken approved tone,
name/subtitle, categories and screenshot direction September 12; guest-first copy
was saved September 13. App Store Connect is authoritative for final submitted
fields. Current review state is in the [release checklist](release-checklist.md);
the [Guideline 2.1 record](app-review-response-2-1.md) distinguishes prepared copy
from owner-reported resubmission. Do not describe V1.1 features as shipped in V1.

## Recommended Positioning

A small daily ritual for people who enjoy cats, imaginative artwork, and a few
quiet words. Lead with the card, not authentication or technical implementation.
Describe the images as artwork, not real cat photographs. Keep the tone warm
and restrained rather than promising self-improvement or therapeutic results.

## Listing Fields

The fenced blocks below contain the approved V1 customer-facing text only.

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
Enjoy your daily card without an account. Optional email and password sign-in is available in Settings. Internet access is needed for account actions; artwork and quotes are included with the app. Password recovery is available on the sign-in screen, and signed-in users can delete their account from Settings. Signing out or deleting your account does not remove access to daily cards.

A small ritual, with whiskers.
```

### Keywords

```text
quotes,kittens,cozy,fantasy,inspiration,reflection,ritual,celestial,whimsical
```

These are relevance-based suggestions, not measured search-volume or ranking
claims. They avoid repeating the approved name/subtitle terms and omit competitor
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

## Screenshot Inventory

Dani approved the cards/order; Ken approved six final compositions, uploaded to
version 1.0. September 14 RC-source visual comparison passed; see
[distribution evidence](distribution-readiness.md#rc-source-screenshot-comparison-september-14-2026).

| Order | Card | Caption |
| --- | --- | --- |
| 1 | celestial_constellation_watcher | A calm cat moment, once per day. |
| 2 | forest_lantern_bearer | A little wonder in your day. |
| 3 | cozy_fireplace_sage | A few words to paws with. |

Three iPhone 6.9-inch compositions are 1320 x 2868; three iPad 13-inch compositions
are 2064 x 2752. All six were verified opaque 8-bit RGB/sRGB. Captions sit outside
complete, uniformly scaled native screenshots; no invented UI or browseable gallery.
Approved exports/provenance are ignored under
`build/screenshots/2026-09-12/compositions/`. See [screenshot tooling](../ci/screenshots/README.md)
for reproduction. Any changed export needs fresh approval and candidate comparison.

## Metadata and Scope

September 28 preflight reconfirmed saved V1 scope; these are dated observations,
not authorization to change settings:

- Free, United States only, public App Store distribution; iPhone and iPad.
- Apple silicon Mac and Vision Pro distribution opted out; manual release selected.
- English (U.S.); Entertainment primary, Lifestyle secondary; standard Apple license.
- Rating: 9+ in 172 territories, regional exceptions (Vietnam/Brazil 12+, Korea All);
  older-than-iOS-26 systems show global 4+ with regional exceptions. Not Made for Kids.
- Copyright entry: `2026 Kenneth Widemon`. Ken identified ChatGPT as the source of
  artwork and quotes, with no third-party photos/artwork/copied quotes used as inputs.
  Owner-approved No third-party content answer was saved and reload-verified.
  This is recorded provenance, not independent copyrightability or rights clearance.
- Free Apps Agreement and DSA declaration Active. Ken confirmed no EU distribution
  planned through the account; reassess before changing scope. No new legal agreement
  is authorized by this document. Paid agreement/banking setup is not part of V1.
- [Privacy disclosures](account-privacy-readiness.md) remain applicable; no accessibility
  support labels are published.
- Operator/public contact: Kenneth Widemon, dailywhiskers.support@gmail.com.
- [Support](https://kenwidemon.github.io/daily-whiskers-site/support/) and
  [privacy](https://kenwidemon.github.io/daily-whiskers-site/privacy/) are saved URLs.

## Reviewer Access

Guest cards need no login. Optional account tools use Settings > Sign In, recovery,
logout and password-confirmed permanent deletion. V1 uses a shared email/password
form; the dedicated registration form is development work, not RC1.

Keep the dedicated working reviewer account in App Store Connect's Sign-In
Information. Ken confirmed its exact-TestFlight login September 28. Test permanent
deletion only with a different disposable account. Sign-in required remains checked
for optional account-tool review, with guest access explained in Notes.

Ken reports uploading the requested recording and resubmitting after Guideline 2.1.
The final sent reply/Notes have not been independently compared with the preparation
draft. Do not overwrite them from an old repo template. App Store Connect holds
final correspondence, attachment and private contact values; no credentials here.
