# Branching Strategy

Ken approved a main-based `release/rc` pre-release testing branch on September 13,
2026, with `codex/develop` remaining the development trunk. This document defines
branch mechanics; the numbered [release checklist](release-checklist.md) remains
the source of truth for release readiness and outstanding work.

## Branch Roles

| Branch | Purpose | Normal source and PR target |
| --- | --- | --- |
| `main` | Stable released code | Accept the tested `release/rc` through a release PR |
| `codex/develop` | Development trunk, potentially ahead of the active release | Accept approved task PRs and release-fix sync PRs |
| `release/rc` | Long-lived pre-release testing and stabilization | Initially branch from `main`; accept reviewed trunk promotions and RC fixes |
| `codex/<task>` | One development task | Branch from updated `codex/develop`; PR back to trunk |
| `codex/rc-<fix>` | A fix for the frozen candidate | Branch from `release/rc`; PR into RC, then propagate to trunk |

```text
main -- initial branch creation --> release/rc

codex/<task> --> codex/develop -- promotion PR --> release/rc -- release PR --> main
                                                   ^
                                                   |
                                             codex/rc-<fix>

release/rc -- accepted-fix sync PR --> codex/develop
main -- released-baseline sync PRs --> release/rc and codex/develop (when needed)
```

Creating RC from `main` establishes its stable baseline. It does not mean a new
feature is developed on `main`, nor does it make the initial RC an accepted build.

## Promotion and Freeze

1. Merge approved task PRs into `codex/develop`. Ken approves the release scope
   before a promotion PR from `codex/develop` into `release/rc` is merged.
2. Review the whole promotion diff and pin the approved head SHA. New trunk commits
   change an open promotion PR; they require review and checks again. Once the
   promotion is merged, later trunk work does not enter RC automatically.
3. Freeze the RC scope. Permit release-blocking fixes, approved configuration or
   metadata changes, and release documentation, not unrelated features/refactors.
4. Run CI and scoped physical acceptance, then archive/export/validate from the
   exact RC commit. With owner approval, identify candidates using immutable tags
   such as `v1.0.0-rc.1` (example naming, not a created tag or an app-version change).
5. Record source SHA, candidate tag, app version/build, and archive/export hashes.
   TestFlight and review must use the identified artifact. A changed candidate
   requires fresh artifacts and relevant checks; do not move an existing tag or
   reuse an already-uploaded build number for different code.
6. When accepted, open `release/rc` into `main`. Verify that the proposed merged
   source tree matches the tested RC. If `main` has gained changes, reconcile them
   into RC through a PR and retest before release; do not silently change the
   candidate at the promotion step.
7. Preserve ancestry with merge commits for trunk/RC/main promotion and sync PRs.
   Do not squash or rebase-merge these long-lived branch promotions. The main
   merge SHA can differ from the RC SHA; retain the tested RC/artifact provenance
   rather than claiming the archive was built from a later merge commit.
8. Record the release tag/commit on `main` when authorized. Keep the RC branch;
   synchronize the released baseline and fixes back to RC/trunk through PRs where
   needed. Do not reset or force-push it between releases. Start the next cycle
   with a new reviewed trunk promotion.

## Candidate Fixes

- Cut `codex/rc-<fix>` from the current RC and PR into `release/rc`. Run the same CI
  and the checks relevant to the fix before merging.
- After each accepted fix, open a sync PR from `release/rc` into `codex/develop`.
  Resolve conflicts in a separate `codex/<task>` branch if needed; preserve newer
  trunk work. Do not let a release-only bug fix disappear from the next version.
- A fix developed on trunk can be ported onto an RC fix branch instead of merging
  unrelated trunk changes. Document the source commit and verify the port.
- An urgent production hotfix starts from `main` and requires its own approved
  PR. Bring it into RC and trunk, then revalidate any active candidate affected by
  the change. A hotfix is not permission to bypass review or release approval.

## CI and Protection

The iOS workflow includes pushes to, and PRs targeting, `main`, `codex/develop`,
and `release/rc`. It runs the existing build/unit-test job, not an automatic
archive, upload, deployment, or UI/physical acceptance suite.

Repository settings to verify/configure separately for all three long-lived
branches: require PR review and the `Build and unit tests` status check, rerun
review/checks when a promotion changes, and prohibit force pushes/deletion.
Use review settings that invalidate stale approval when new commits arrive.
Do not require linear history on these branches: promotion/sync PRs use merge
commits. Workflow filters alone do not enforce branch protection; no protection
rules were changed by this documentation/CI update. Ensure CI is actually running
on the first RC promotion before treating it as a gate.

## Initial RC Record (Historical)

- `release/rc` was created locally and published from `origin/main` at
  `db25664e0b8423d80f23e93bab7fd4bfb4531d0c`, without promoting trunk work.
- Guest-first PR #41 subsequently merged into `codex/develop` at
  `0a2c4ffd08b9fde25f13d2c75f4a5f8bcd8f81e8`. It is not yet in RC.
- Strategy/CI PR #42 merged into `codex/develop` at
  `07a34032e2bce166c24094b96e2df6734a4d1738`. The change is no longer awaiting merge.
  The first approved development-to-RC promotion must include it.
- No candidate/release tag, RC promotion, App Store upload, submission, or manual
  release is authorized merely by creating this branch.

## First Promotion and Freeze (September 14, 2026)

- PR #46 merged into `release/rc` at
  `20ae9cd3d664c3c412a2489ea7304449f1e0b8e2`, with parents
  `db25664e0b8423d80f23e93bab7fd4bfb4531d0c` and
  `00f246689d876a8ff28718960b606cb40843c037`. The resulting tree exactly matches
  the reviewed develop head, including guest-first, strategy/CI, and QA evidence.
- Ken authorized candidate preparation; annotated tag `v1.0.0-rc.1` was created
  and published at that merge. Do not move it for later fixes or documentation.
- RC push CI passed. Fresh regression/archive/export/validation evidence and
  pending final acceptance are tracked in the
  [RC1 record](distribution-readiness.md#rc1-artifact-record-september-14-2026).
- `main` is unchanged. No upload, submission, or release has occurred.
