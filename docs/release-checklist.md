# V1 Manual Release Checklist

Canonical V1 release gates. Preserve item numbers and explicit deferrals.
Updated September 28, 2026. **Ken reports the requested Guideline 2.1 material is
uploaded and the app resubmitted; Apple's next decision is pending.** Exact live
status and final sent Notes have not been independently rechecked. Manual release
remains the approved policy; no public release is recorded.

## Release Gates

1. **Complete by owner report: final physical acceptance.** Ken confirmed exact
   TestFlight `1.0 (1)` iPhone/iPad guest/account flows, VoiceOver/larger text, and
   natural overnight foreground rollover without force-quitting or updating.
   Named devices: iPhone 13, iPhone 17 Pro Max, iPhone 18 Pro Max; iOS 27.0 was
   reported, followed by explicit confirmation of iOS 26 testing. The iPad model,
   OS patch versions, per-device mapping and overnight date/device were not supplied.
   Do not infer them from beta feedback or the later review recording.
2. **Complete within approved scope, with V1 deferrals.** September 13 local
   Release checks passed by owner report for three ordinary launches, no obvious
   card stutter/freezes, and five foreground cycles. September 14 overnight
   foreground rollover passed by owner report, supported by unchanged PID and
   installation path on iPhone 17 Pro Max / iOS 26.6.2. Exact-TestFlight rollover
   was subsequently confirmed under #1. Detailed startup/hitch, memory-pressure,
   battery/long-session and lower-memory testing remain approved post-V1 deferrals,
   not passing measurements. See [testing limits](testing.md#v1-deferrals-and-performance-evidence).
3. **Complete: security/product decisions.** Ken reported disabling the legacy
   development account in Firebase; disabled state/token revocation were not
   independently verified. Dani approved guest-first access with optional account
   tools. Guest access creates no anonymous Firebase account. Public privacy/support
   pages and V1 listing copy were reconciled. Do not reuse exposed credentials.
4. **Complete by owner report: reviewer access.** Dedicated credentials are saved
   in App Store Connect; Ken confirmed sign-in on exact TestFlight `1.0 (1)` on
   September 28. Keep this account available, and use a different disposable
   account for deletion tests. No credentials belong in Git or chat.
5. **Complete: account/metadata readiness.** September 28 preflight verified
   free/U.S.-only availability, manual release, Mac/Vision Pro opt-outs, metadata,
   screenshots, public URLs, Active Free Apps Agreement and Active DSA status.
   Ken approved the no-EU-distribution declaration and exempt-encryption setting.
   The RC's packaged `ITSAppUsesNonExemptEncryption` is Boolean false. Reassess
   changed business scope, data use or dependencies; prior approval is not blanket
   authorization for new declarations or legal agreements.
6. **Complete: accepted RC1 promoted to main.** Immutable `v1.0.0-rc.1` identifies
   `20ae9cd3d664c3c412a2489ea7304449f1e0b8e2`. PR #66 promoted accepted RC to main;
   PR #67 synced main history into development. Archive/export/server validation,
   57 RC unit tests and six RC-source screenshot comparisons passed September 14.
   Preserve [artifact provenance](distribution-readiness.md#rc1-artifact-record-september-14-2026);
   do not substitute a newer development build or retag/rebuild this candidate.
7. **Complete by owner report: TestFlight distribution and scoped acceptance.**
   Authorized upload completed September 14; September 28 observed Testing in
   internal and Family & Friends groups. Ken confirmed exact-build acceptance,
   including the specifically requested iOS 26 baseline. This is not a waiver or
   independently observed physical test. Three beta reports established no new
   blocker; existing password-visibility/widget requests remain backlog work.
   Empty Crash Feedback is not proof of zero crashes.
8. **Resubmitted by owner report; Apple's next decision pending.** Initial
   submission of `1.0 (1)` was observed September 28 at 1:58 PM EDT as Waiting for
   Review, submission `c7648ecf-cc4a-4d87-b014-d7c5e1a8b9e4`. Ken then supplied
   Apple's 7:18 PM Guideline 2.1 request and reported uploading everything and
   resubmitting. Sampled recording frames show TestFlight `1.0 (1)` and the
   requested account flows. Ken confirmed iPhone 17 Pro Max / iOS 27.0.1 for that
   recording. Final sent Notes, attachment processing, selected resubmission build,
   submission ID and live status remain independently unverified. See the
   [review record](app-review-response-2-1.md). Do not duplicate the submission.
9. **Not started: manual release after approval.** At Pending Developer Release,
   verify approved build, availability, reviewer outcome and remaining risks.
   Perform the final go/no-go with Ken and release only with explicit approval.
   Respond to further review feedback and retest any resulting app changes first.

## Boundaries and Follow-ups

- The phone largest-text landscape simulator failure is explicitly deferred for
  V1. Preserve the software-keyboard precondition and full-button visibility
  assertion; do not mark the suite green or weaken the test to close this gate.
- DW-005/DW-006 development work does not enter frozen V1 automatically. Follow
  the [branching strategy](branching-strategy.md) for a replacement candidate.
- The shared checkout's untracked Xcode Cloud folder was explicitly deferred by
  Ken. This documentation cleanup does not stage, delete or configure it.
- Older Step 4A/4B/5 labels were development phases, not these item numbers.
  Historical detail is recoverable through the [documentation map](README.md#historical-recovery).
