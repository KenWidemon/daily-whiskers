# Documentation Map

Keep current engineering guidance and concise release evidence in Git. Store
workflow status in GitHub, final review correspondence in App Store Connect,
and personal planning in Apple Notes. Updated September 28, 2026.

## Start Here

| Document | Responsibility |
| --- | --- |
| [App README](../DailyWhiskers/README.md) | Current development behavior, setup, Firebase, test commands, CI |
| [Branching strategy](branching-strategy.md) | Trunk/RC/main roles, promotions, fixes, authorization boundaries |
| [Testing](testing.md) | Repeatable acceptance checks, unresolved risks, scoped development evidence |
| [Content pipeline](content-pipeline.md) | Manifest and asset maintenance |
| [Screenshot tooling](../ci/screenshots/README.md) | Isolated preview/export procedure, not functional acceptance |
| [Release checklist](release-checklist.md) | Canonical V1 gates and remaining work; preserve item numbers |
| [Distribution record](distribution-readiness.md) | Frozen RC identity, hashes, upload/promotion provenance, archive procedure |
| [Release configuration](release-readiness.md) | Signing identity, Firebase configuration, debug credential safety |
| [Account/privacy](account-privacy-readiness.md) | Account lifecycle, data inventory, disclosures and policy decisions |
| [App Store listing](app-store-listing.md) | Approved V1 customer-facing copy, screenshot inventory, metadata |
| [App Review record](app-review-response-2-1.md) | Guideline 2.1 request, owner-reported resubmission, recording evidence |
| [Backlog navigation](backlog.md) | Links to canonical GitHub Issues/Projects, not a duplicate roadmap |
| [Agent guidance](../AGENTS.md) | Apply repository conventions during agent work |
| [PR template](../.github/pull_request_template.md) | Prompt authors/reviewers to check evidence, scope and documentation |

## Where Notes Belong

- **Git:** behavior contracts, reproducible procedures, privacy facts, candidate
  provenance, concise acceptance results and explicit unresolved risks. A source
  change and its necessary documentation should be reviewable together.
- **GitHub Issues/Projects:** feature scope, priorities, acceptance work and PR
  discussion. Do not maintain live issue status in README session journals.
- **App Store Connect:** the actual submitted reply, reviewer credentials/contact,
  review attachments and Apple's decisions. Repo drafts are not proof of sent text.
- **Apple Notes / Side Hustle:** personal planning, product discussions, and a
  human-readable project journal. Notes are supplementary, not the release gate
  or technical source of truth. Never store account passwords or reset links there.
  The September 28 snapshot is named **Daily Whiskers - V1 Release Journal**;
  earlier kickoff notes remain historical proposals, not current requirements.
- **Private artifact storage:** videos, raw logs/traces, archives, IPAs, signing
  profiles and screenshots. Use access-controlled, backed-up storage; do not
  commit these or assume a temporary path is durable.

## Admission Rule

Default to updating an existing canonical document, not creating another file.
Keep documentation in Git only when all three conditions hold:

1. It helps a contributor build, operate, maintain, test, or safely release this code,
   or explains a consequential technical/product constraint on the implementation.
2. It needs versioning with the code or provides minimal, auditable release evidence.
3. It has one clear home, no secrets/private user data, and a defined update trigger.

Examples worth keeping: setup commands, behavior contracts, non-obvious design
decisions, repeatable test procedures, data/privacy boundaries, approved listing
source, and compact candidate identity/acceptance records. Public contact details
intended for the listing are not private credentials.

Do not add session recaps, handoff diaries, copied chat/review threads, run-by-run
test output, temporary troubleshooting logs, duplicate roadmaps, or speculative
feature plans. Use issue/PR discussion for implementation details, Side Hustle for
personal planning, App Store Connect for review correspondence, and private artifact
storage for raw evidence. Keep only the resulting decision, risk or durable
procedure in Git. A link to private material must not be the only explanation of
a constraint that a contributor needs to understand.

## Review and Retention

- The author owns documentation affected by a change; the PR reviewer checks it.
  Update behavior/setup/configuration/privacy guidance in the same PR that changes
  it. No relevant documentation change is a valid outcome; do not manufacture one.
- Every new document needs an entry in Start Here stating its responsibility.
  Its introduction must identify its scope and update trigger. Prefer a section in
  an existing guide when the responsibility overlaps.
- Keep procedures current; keep release evidence explicitly dated and tied to its
  candidate. Summarize acceptance as result, scope, provenance and remaining risk,
  with a reference to detailed evidence rather than pasted transcripts or test logs.
- At PR review, check duplication, stale instructions, links, sensitive data and
  whether changed behavior is documented. The PR template is a human review gate,
  not an automated guarantee. Do not add dated verification appendices to README.
- At candidate freeze and release closure, reconcile the numbered release checklist,
  preserve compact provenance/decisions/waivers, and retire temporary coordination
  text. The Guideline 2.1 record is current review evidence, not a journal to extend
  forever; after review closes, retain the outcome and material constraints.
- Remove obsolete guidance once its replacement and necessary evidence are retained.
  Git history is the archive for committed prose; do not add a repo archive folder.
  Before deleting unique uncommitted material, preserve and verify a private copy.
  Never erase unresolved risks or treat missing evidence as a pass.
- External destinations are not automatic backups. Confirm a successful save and
  appropriate access before removing unique material; if unavailable, leave it in
  place and report the blocker. Do not migrate credentials or rewrite Git history.

## Maintenance Rules

- Update the linked issue's project status as part of making progress, without
  waiting for Ken to move it manually. Verify live status/options and preserve
  owner edits before each transition: **In Progress** when implementation starts;
  **In Review** when the change is ready for review; **Done** only when the agreed
  scope is completed, required acceptance is satisfied or explicitly waived, and
  applicable implementation PRs are merged. A draft PR or partial test pass alone
  does not complete an item. Keep unfinished draft work In Progress and record
  completed work, remaining checks, and deferrals in the issue with its PR link.
  Recheck status at implementation start, PR readiness, material acceptance
  updates, and merge/completion; leave it unchanged when the phase has not changed.
  Read back updates, report access failures, and label stale migration-era status
  in issue bodies as historical rather than maintaining duplicate live status.
- Update release status only in the canonical checklist; other documents should
  link to it rather than accumulate competing next-step lists.
- Label each acceptance result with its build/source, date, device/OS when known,
  and whether it was observed or owner-reported. Unknown details stay unknown.
- An old test count, stopped simulator or trace path is not current machine state.
  A deferral is not a passing test. UI hierarchy checks do not prove VoiceOver.
- Keep private contacts, credentials, user recordings, and Firebase configuration
  out of Git. Removing text does not purge history or revoke exposed credentials.
- Update local links when moving documents. Documentation cleanup does not
  authorize backend changes, uploads, legal agreements, resubmission, or release.

## Historical Recovery

The September 28 cleanup removed long session journals, obsolete setup failures,
original photo-sequence mapping, and the superseded response template. Relevant
outcomes and open risks remain in the guides above; no Git history was rewritten.

Tracked pre-cleanup documents are recoverable at commit
`f465059a68cccf07eb9199972ddc871b4ce54da7`, for example:

```sh
git show f465059a68cccf07eb9199972ddc871b4ce54da7:docs/performance-qa.md
```

A checksummed local snapshot also preserves all 15 documents, including the
uncommitted review-response draft, before cleanup:
`~/Documents/Codex/Archives/Daily Whiskers/docs-cleanup-20260928-203052/`.
This local copy is not a shared/cloud backup. Its README and SHA256SUMS describe
recovery. Historical instructions are not tasks to repeat; referenced temporary
artifacts may no longer exist. Raw artifacts were not moved or deleted.
