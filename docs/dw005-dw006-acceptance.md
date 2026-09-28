# Account Form Acceptance — DW-005 and DW-006

Use one physical-device session for [DW-005](https://github.com/KenWidemon/daily-whiskers/issues/54)
and [DW-006](https://github.com/KenWidemon/daily-whiskers/issues/55), recording results
against each issue separately. GitHub Projects owns live workflow status. This
checklist is an acceptance procedure, not a release approval or a record of passes.

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
  See the [app README](../DailyWhiskers/README.md#physical-registration-check--owner-report-september-28-2026).
- DW-005: iPad physical checks and live-request VoiceOver progress/backend-error
  checks remain untested. Firebase policy alignment is explicitly deferred: client
  registration requires eight characters and ASCII uppercase/lowercase/digit;
  Firebase remains minimum six with no required classes. Do not change policy as
  part of this pass or label this mismatch resolved.
- DW-006: new physical acceptance is required. The existing Sign In largest-text
  landscape simulator deferral is independent of the reported registration pass;
  preserve its original test and report any new result against its actual device.
- Keep both issues open until their agreed criteria are accepted or explicitly
  waived and applicable merges are complete. No merge, release, backend-policy
  change, or automatic live account mutation is authorized by this checklist.
