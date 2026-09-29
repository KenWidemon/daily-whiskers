# Account Form Acceptance — DW-005 and DW-006

Use one physical-device session for [DW-005](https://github.com/KenWidemon/daily-whiskers/issues/54)
and [DW-006](https://github.com/KenWidemon/daily-whiskers/issues/55), recording results
against each issue separately. GitHub Projects owns live workflow status. This
checklist defines the procedure; dated results below record only the checks exercised.
It is not release approval.

## Physical Session Setup (September 28, 2026)

- Agent verified both connected physical devices: iPhone 17 Pro Max and iPad Pro
  13-inch (M4), each running OS 27.0 (24A437).
- Built signed Debug version 1.0 (1) from clean tracked source at
  `a860af90a32d52ef10cd10b9279c266ab31c0cd2` with Xcode 27.0. The deferred untracked
  Xcode Cloud directory remains excluded. Build, installation and launch succeeded
  on both devices through `devicectl`; no debug test-account credentials were supplied.
- Ken selected Apple Passwords for the AutoFill checks on both devices.
- Executable SHA-256: `8b2bacb88b6e745872fba7e43fc1d38a3fbe1d497c41bcd97c83056e5d4e48a3`.
  Debug library SHA-256: `9a820e7e7474ae78651c00176207f71a01a05ad818b65dc8afb87dc965df32db`.
- Local build log: `/tmp/dw006-physical-build.log`; installed app:
  `/tmp/dw006-physical-derived/Build/Products/Debug-iphoneos/DailyWhiskers.app`.
  Install/launch receipts are `/tmp/dw006-{phone,ipad}-{install,launch}.json`.
  These temporary local receipts are not distribution artifacts.
- Setup was agent-verified. Behavioral results below are owner-reported and
  scoped to the named round; they do not imply untested criteria passed.

## Round 1 — DW-006 Sign In Editing and Privacy

Ken reported “iPhone pass / iPad pass” on September 28, 2026, for the guided
round using the installed build and devices above:

- Password starts masked after opening optional Sign In.
- Show/Hide preserves typed text, keyboard and editing focus while appending input.
- Selecting a middle range, toggling visibility, then replacing that selection
  retains the expected text and selection behavior.
- Switching to another app while revealed and returning masks the retained value.
- Closing Sign In and reopening clears the password and restores masking.

Email was left empty and no authentication request was submitted. This round did
not exercise Apple Passwords, VoiceOver, large text, device locking, swipe
dismissal, an unfocused visibility toggle, or live requests. Acceptance was ongoing
at this checkpoint.

## Round 2 — DW-005 Registration Editing and Privacy

Ken reported “iPhone pass / iPad pass” on September 28, 2026, for the next guided
round on the same installed build and devices:

- Opening registration from populated, revealed Sign In fields prefills only email;
  both registration passwords are empty and the eight-character/uppercase/lowercase/
  number guidance is visible.
- Password and confirmation reveal independently. Each retains text, editing focus
  and keyboard through Show/Hide and continued typing.
- Each field preserves its middle selection through visibility changes and allows
  replacing it with the expected resulting value.
- Switching apps with both passwords revealed masks both on return, retaining input.
- Back to Sign In shows an empty, masked Sign In password (also DW-006 evidence).
  Reopening registration shows both registration passwords empty.

No registration request was submitted. These are owner-reported behavior passes,
not AutoFill, VoiceOver, local-validation, large-text or live-request acceptance.
Registration Close/swipe dismissal and device locking were not exercised in this
round. The iPad now has scoped physical editing/privacy evidence; its remaining
physical checks are still pending. Firebase policy alignment remains deferred.

## Round 3 — Local Validation (DW-005 and DW-006)

Ken reported “iPhone pass / iPad pass” for the guided local-validation round on
both devices and the installed build identified above.

- DW-005: Empty registration fields show the valid-email error. With a valid-format
  synthetic email, the five submitted invalid cases each show the expected error:
  seven-character password, missing uppercase, missing lowercase, missing digit,
  and mismatched confirmation. Each attempt stays on registration with readable
  feedback; no valid registration was submitted.
- DW-006: With a valid-format email, five-character Sign In input disables submission
  and six-character input enables it. Sign In was not submitted. With email cleared,
  two Forgot password attempts each show the valid-email error.

These are owner-reported local behavior results. They do not establish VoiceOver
speech/focus, backend enforcement, successful authentication, reset-email delivery,
AutoFill or layout at larger text sizes. No account creation or reset email was
part of this round. Firebase alignment remains deferred.

## Round 4 — Apple Passwords AutoFill (DW-005 and DW-006)

Ken reported the following on both iPhone and iPad for the installed build above:

- DW-006: Sign In AutoFill passed using Apple Passwords.
- DW-005: A registration strong-password suggestion was offered and confirmation
  filled automatically.
- Editing after AutoFill passed on both devices in the guided round, which called
  for Show/Hide and continued editing of the filled fields without submitting.

This supplies named-manager, current-build physical evidence for both forms and
both devices. Neither form was submitted in this round. Results are owner-reported;
VoiceOver, large-text layout and live-request acceptance continue separately.
These results do not establish Firebase policy alignment or other managers' behavior.

## Identify the Build

Record source commit (and any uncommitted changes), app version/build, installation
source, device, iOS version, and password manager used. Build the DW-006 task branch
for this round; an older DW-005 binary cannot validate the new Sign In control.
Use a controlled account for explicitly chosen live checks. Never put passwords,
reset links, or account addresses in the evidence. Automated tests use synthetic
input and injected operations; they do not prove live auth or password-manager use.

## Shared Physical Session

Run on iPhone and iPad, in portrait and landscape where applicable. Mark each
row passed, failed, not run, or explicitly deferred; record who observed it.

| Check | DW-006 Sign In | DW-005 Create Account |
| --- | --- | --- |
| Entry and guest access | Settings opens optional Sign In with a masked, empty password. Close/swipe returns to the same daily card. | Create Account opens a separate form without a request; only email is prefilled. |
| Visibility and editing | Type, move the caret into the middle, select a range, toggle both ways, replace the selection, and keep typing. Value, selection, focus and keyboard stay intact. Toggle also works without focusing the field. | Repeat for password and confirmation independently. |
| Privacy lifecycle | Reveal, switch apps/lock and return: masked with input retained. Close/swipe and reopen: masked with draft discarded. Going to registration and back also clears/masks the Sign In password. | Reveal both, background and return: masked. Back or Close discards both registration passwords. |
| AutoFill | Fill an existing credential with the named manager. Reveal/hide and edit without losing it or unexpectedly offering a new password. | Generate/fill a compliant new password and confirmation with the named manager; confirm both remain editable. Do not submit merely to test AutoFill. |
| VoiceOver controls/privacy | Fields and Show/Hide action and Hidden/Visible state are identified; focusing either masked or revealed password does not read its contents. Navigate away/back and edit; no focus trap. | Repeat for both password controls and Back/Close. |
| Local validation | Existing six-character passwords remain eligible; invalid email/short input cannot sign in. Forgot password with empty/invalid email gives accessible feedback repeatedly. | Invalid email, minimum eight, ASCII uppercase/lowercase/digit and exact confirmation each block submission with accessible feedback and error focus. |
| Largest accessibility text | With keyboard open, scroll to password, visibility control, reset and primary/navigation actions in portrait and landscape. Check clipping, overlap and 44-point targets. | Repeat for all three fields, both visibility controls, submit and Back. |
| Pending request and failure | With an owner-controlled request, verify progress speech, disabled duplicate actions/dismissal, accessible backend/network failure and retry. | Repeat registration request checks; creating a real account is a separate deliberate test action. |
| Success and recovery | Controlled successful sign-in returns to the same daily card. Verify reset behavior only with deliberate authorization to send an email. | Controlled registration success follows the existing session route to the daily card. |

A layout/element-tree assertion does not establish VoiceOver speech or real
password-manager behavior. A successful request does not prove reset delivery.
Do not infer a pass for an unexercised row from confidence in the implementation.

## Prior Evidence and Remaining Boundaries

- DW-005: Ken reported registration basics, editing/visibility/background masking,
  guided AutoFill, local VoiceOver and largest-text portrait/landscape checks passed
  on iPhone 17 Pro Max / iOS 27 with implementation `a7b37a3`. The password manager
  was not identified and installed binary identity was not independently verified.
  See the [DW-005 testing evidence](testing.md#dw-005-development-evidence).
- DW-005: At the prior checkpoint, iPad physical checks and live-request VoiceOver
  progress/backend-error checks were untested. The dated rounds above supersede
  only the specific checks exercised. Firebase policy alignment remains deferred:
  client registration requires eight characters and ASCII uppercase/lowercase/digit;
  Firebase remains minimum six with no required classes. Do not change policy as
  part of this pass or label this mismatch resolved.
- DW-006: Rounds above record scoped current-build physical passes. The next
  VoiceOver round has been issued but no result has been reported. Large-text
  layout and live-request checks also remain pending. The historical Sign In
  largest-text landscape simulator deferral is independent of these results;
  preserve its original test and report new results against their actual devices.
- Keep both issues open until their agreed criteria are accepted or explicitly
  waived and applicable merges are complete. No merge, release, backend-policy
  change, or automatic live account mutation is authorized by this checklist.
