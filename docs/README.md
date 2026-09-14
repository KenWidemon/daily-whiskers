# Documentation Map

Reviewed September 13, 2026. Start with the document matching the question below.

## Current Guidance

| Document | Use it for |
| --- | --- |
| [Release checklist](release-checklist.md) | **Canonical remaining work**, stable item numbers, owner decisions, and release gates |
| [App README](../DailyWhiskers/README.md) | Current behavior, local setup, content, and test commands |
| [Branching strategy](branching-strategy.md) | Development, RC promotion, fixes, and release PR mechanics |
| [App Store listing](app-store-listing.md) | Saved customer/reviewer copy and dated App Store entry evidence |
| [Release configuration](release-readiness.md) | Identity, Firebase configuration, debug credentials, and historical signing evidence |
| [Distribution readiness](distribution-readiness.md) | Archive/export procedure and dated artifact evidence, not an accepted current candidate |
| [Account/privacy audit](account-privacy-readiness.md) | Account lifecycle, data inventory, published policy, and decision provenance |
| [Image import guide](../DailyWhiskers/Resources/CAT_IMAGE_IMPORT.md) | Current asset layout and historical first-import mapping |
| [Screenshot tooling](../ci/screenshots/README.md) | Reproduce isolated previews; no live auth or distribution acceptance |

## Evidence, Not Competing Roadmaps

| Document | Status and limits |
| --- | --- |
| [Accessibility and interaction QA](accessibility-interaction-qa.md) | Historical runs plus scoped September 13 guest-first iPhone acceptance; final-candidate repeats remain |
| [Performance QA](performance-qa.md) | Historical measurements, removed harness provenance, and unresolved measurement gaps; checklist #2 controls next work |
| [Visual readability QA](visual-readability-qa.md) | Historical Step 4A layout evidence, superseded for readiness by later interaction QA |

Every existing document has useful evidence or operational guidance, so none was
deleted in this audit. The former Step 4A/4B/5 labels are development history;
they are **not** the current numbered release checklist. In particular, historical
"step 2" scrolling acceptance is not current checklist #2 performance acceptance.

## Status Rules

- Update the release checklist first when work closes or the owner defers it.
  Link detailed evidence rather than copying a second numbered release roadmap.
- Read dated results against their recorded source/build/device. A passing old
  test count or archive is not a result for current code. September 9 archives
  predate VoiceOver and guest-first changes and must not be shipped as the RC.
- Preserve historical failures and later resolutions together. Mark superseded
  instructions explicitly; do not convert unresolved tests into passes.
- Paths in `/tmp`, system temporary directories, and ignored `build/` directories
  are provenance references, not guaranteed available artifacts. Check existence
  before use; missing traces do not authorize invented results or automatic reruns.
- Record owner-reported and agent-verified evidence separately. Never include
  passwords, reset links, private review contact details, or Firebase secrets.
- Old statements such as "simulators shut down" describe that session only.
  Inspect current state before claiming a device, process, branch, or service state.
- Documentation edits do not authorize external metadata changes, legal
  agreements, RC promotion, uploads, review submission, or manual release.
