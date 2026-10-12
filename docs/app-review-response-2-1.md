# App Review: Guideline 2.1 Record

For V1 `1.0 (1)`, frozen at `v1.0.0-rc.1`. Current gates live in the
[release checklist](release-checklist.md), not in this dated evidence record.
DW-005/DW-006 are not part of the submitted RC1 binary.

## Request and Response Scope

Ken supplied Apple's September 28, 2026, 7:18 PM message: Guideline 2.1,
Information Needed, New App Submission. Apple cited limited developer review
history and requested six items, without identifying a specific code defect:

1. Physical-device recording on the latest OS, beginning with launch and showing
   normal use, registration/login/deletion, and any UGC or paid-content flows.
2. Purpose/audience: a brief entertainment ritual for people who enjoy illustrated
   cats and reflective quotes, not a therapeutic or regulated service.
3. Setup/main features: immediate guest card; optional V1 shared email/password
   form, reset, logout and password-confirmed deletion in Settings; no sample files.
4. Services: Firebase Auth/Core for optional accounts, GitHub Pages for public
   support/privacy. ChatGPT prepared bundled art/quotes; no runtime AI or remote
   daily-content service, ads, purchases, subscriptions or UGC feed.
5. Regional scope: U.S.-only distribution, English, no region-specific features;
   local calendar date can change the selected card across time zones.
6. Regulated/content context: no regulated service; Ken confirmed ChatGPT-generated
   art/quotes without third-party photos/art/copied quotations as inputs. This is
   provenance, not independent legal clearance or a claim of exclusive copyright.

The six-part local response was prepared for the reply and replacement Notes.
Its exact final sent wording has not been independently verified. App Store Connect
is authoritative; do not overwrite its Notes with a historical draft. The full
preparation template is preserved in the [local snapshot](README.md#historical-recovery),
not retained here with unresolved submission placeholders.

## Owner-Reported Resubmission

After draft preparation, Ken confirmed: "Uploaded everything and re-submitted
for review." Record the upload and resubmission as owner-reported completion,
not agent-observed App Store Connect state or Apple acceptance of the response.
Ken subsequently confirmed the recording device as **iPhone 17 Pro Max running
iOS 27.0.1**. This is owner-confirmed recording metadata, not inferred from frames
or a claim about every earlier acceptance run.
The final sent text, selected submission build, submission ID,
and exact current status were not independently inspected. The supplied recording
was subsequently inspected as recorded below. Do not invent missing
details or treat preparation text as verified sent wording. Next: await
Apple's response, then the separately authorized manual-release decision.

## Supplied Recording Review

Ken supplied `ScreenRecording_09-28-2026 20-01-27_1.mp4` and identified it as the
uploaded recording. Duration: approximately 2 minutes 45 seconds. The agent
inspected local frames at three-second intervals and closer-spaced frames during
registration; this was not continuous playback or an audio/accessibility audit.
The video and extracted frames remain outside Git; do not publish them as docs.

- 0:00-0:07: TestFlight lists Daily Whiskers `1.0 (1)`, followed by the daily card
  and a guest Settings menu. The recording starts in TestFlight, not mid-flow.
- 0:10-0:43: Privacy Policy and Support pages are displayed and scrolled.
- Around 1:19: an invalid-login message appears before registration.
- 1:25-1:28: Creating Account appears, followed by the daily card. Signed-in
  Settings is visible around 1:34, followed by guest Settings around 1:40.
- Around 1:55-2:01: the login form dismisses to the card and signed-in Settings.
- 2:04-2:19: deletion form, password entry, Delete Permanently confirmation,
  return to the card, and guest Settings are visible. This supports the UI
  deletion flow, not an independent Firebase backend audit.
- Around 2:34: another invalid-login message appears after deletion. The footage
  later returns to the card with a password-save prompt. Do not infer backend
  state or the final session state from that prompt alone.
- Ken confirmed iPhone 17 Pro Max and iOS 27.0.1 for this recording. The inspected
  frames do not independently establish the model/OS or that the OS was the
  latest available release at recording time.
  TestFlight's displayed build identifies the demonstrated version; the App Store
  Connect attachment and selected resubmission build were not independently checked.
- Browser start-page/iCloud-tab information and an account autofill suggestion
  briefly appear. No cleartext password was observed in sampled frames, but this
  is not a frame-by-frame privacy clearance. Keep the recording limited to review.

The observed flows support Apple's requested functionality demonstration. Do not
withdraw or duplicate the resubmission solely to replace this recording; await
Apple's response. Preserve the distinction between observed flows and
owner-confirmed device/OS metadata above.

## Review Safety

Keep the dedicated reviewer account available and use a separate disposable
account for deletion. Credentials/contact values stay in the dedicated secure
fields, not Git, chat or recordings. Keep recordings restricted to review; do
not republish a video containing browser/account suggestions as public marketing.
No duplicate reply, replacement upload or public release is authorized by this record.

[Apple's reply guidance](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages).
