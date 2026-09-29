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
