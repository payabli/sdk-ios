# Branch Protection Rules

This document mirrors the branch-protection configuration set on
`payabli/sdk-ios` (private source repo) and `payabli/payabli-sdk-ios`
(public distribution repo). GitHub doesn't export this config as code, so
when the rules are edited on GitHub they must also be updated here. Treat
this as the authoritative spec — if the UI config drifts from this doc,
the doc wins.

## Private repo (`payabli/sdk-ios`) — 3 long-lived branches

### `develop`

- **Require a pull request before merging:** yes.
- **Required reviews:** 1 approving review.
- **Require status checks to pass:** `CI / Build & Test`, `CI / Lint`,
  `CI / Podspec lint (rendered)`.
- **Require branches to be up to date before merging:** yes.
- **Require linear history:** not required (merge commits are OK since
  the commit count drives versioning).
- **Allow force pushes:** disabled.
- **Allow deletions:** disabled.
- **Bypass:** repo admins only, in break-glass scenarios.
- **Allowed source branches:** `feature/*`, `fix/*`, `chore/*`.

### `sandbox`

- **Require a pull request before merging:** yes.
- **Required reviews:** 2 approving reviews.
- **Required status checks:** same as `develop`.
- **Require linear history:** **yes**. Sandbox PRs should be merges of
  `develop` with a clean history so the commit count stays sensible.
- **Allow force pushes:** disabled.
- **Allow deletions:** disabled.
- **Allowed source branches:** `develop` only.

### `main`

- **Require a pull request before merging:** yes.
- **Required reviews:** 2 approving reviews.
- **Required status checks:** same as `develop` and `sandbox`.
- **Require linear history:** **yes**.
- **Allow force pushes:** disabled.
- **Allow deletions:** disabled.
- **Allowed source branches:** `sandbox` only.

### Tags on the private repo

The release pipeline does **not** create tags on the private repo — tags
only exist on the public distribution repo (see the Public repo section
below for the rules that protect them). The private repo only carries
the historical `0.1.0`–`0.4.0` legacy tags preserved on `main-backup`
after the one-time migration, which are immutable archival refs and
should have `Restrict deletions` enabled to prevent accidental cleanup.

## Public repo (`payabli/payabli-sdk-ios`) — distribution mirror

Only has `main`. `main` only advances on **Production** releases; QA and
Sandbox releases publish tags pointing at orphan commits (see
`Scripts/push_to_public_repo.sh` and `docs/RELEASE.md §Public repo
branching model`).

### `main` branch ruleset

- **Require a pull request before merging:** no. The only writer is the
  release bot using `PUBLIC_REPO_PAT`. The PAT owner is in the
  Bypass list; all other identities are blocked from pushing.
- **Restrict who can push:** the single GitHub identity holding the PAT
  (see `PUBLIC_REPO_PAT` section below).
- **Require status checks:** `validate.yml` (`swift package resolve`
  against the manifest) must pass after each release bot push. This
  catches checksum-mismatch or bad URLs before a partner tries to
  consume the tag.
- **Allow force pushes:** disabled.
- **Allow deletions:** disabled.

### Tag ruleset (release tags live here)

All release tags are created by the release workflow running in the
**private** repo — it clones the public repo, tags, and pushes. The
public repo must protect those tags against mutation or deletion by any
human identity.

- **Target tags pattern:** a single `*.*.*` fnmatch rule is sufficient —
  GitHub's `*` is greedy and matches any content except `/`, so
  `*.*.*` covers GA (`1.0.247`), QA (`1.0.247-qa`), and Sandbox
  (`1.0.247-beta`) simultaneously. Adding separate `*.*.*-qa` and
  `*.*.*-beta` entries is redundant.
- **Rules on the tag target:** `Restrict creations` allowed **only** to
  the release-bot identity; `Restrict updates` enabled; `Restrict
  deletions` enabled. `Require signed commits` off (our tags are
  annotated, not signed). Allow the bot to create; block everyone else.

## `PUBLIC_REPO_PAT` — token reuse decision

The release workflow (`.github/workflows/release.yml`) reads
`PUBLIC_REPO_PAT` directly from the org-level GitHub secret
`GHB_PAT_TOKEN` — the same PAT used by other Payabli release pipelines
(e.g. the `.NET` accounting API).

Tradeoffs accepted:

- **Blast radius:** if `GHB_PAT_TOKEN` is rotated for any other service,
  this pipeline also needs a new value. The owner of the rotation must
  re-grant access to `payabli/payabli-sdk-ios` (fine-grained PAT repo
  allow-list) or re-add the owning user to the Bypass list.
- **Least privilege:** the PAT likely has broader scope than strictly
  needed (it writes to multiple repos). We accept this for v1 to avoid
  the ceremony of provisioning a dedicated fine-grained PAT; the
  branch + tag rulesets on the public repo are the real security
  boundary, not the token's repo allow-list.
- **Auditability:** commits pushed by the workflow will show the PAT
  owner as the pusher in GitHub's UI, while the commit's author/
  committer identity is the `GH_ACTOR`/`GH_EMAIL` configured in the
  workflow ("Payabli Release Bot"). That split is acceptable — the
  workflow run ID in the commit message is the real trace.

When the PAT is rotated, verify:

```bash
TOKEN="..."
curl -sI -H "Authorization: Bearer $TOKEN" \
    https://api.github.com/repos/payabli/payabli-sdk-ios | head -n 1
# expect: HTTP/2 200
unset TOKEN
```

If the response is not 200, the PAT no longer has access to the public
repo and releases will fail at the push step. The owning GitHub user
also needs to appear in the **Bypass list** of both rulesets on the
public repo (main branch + tag).

## Migration checklist

When provisioning a fresh environment (or during the one-time
main-v2 → main migration), apply these in order:

1. Create branches: `develop`, `sandbox`, `main` all pointing at the same
   initial commit.
2. Apply the rules above in GitHub Settings → Branches.
3. Set `main` as the **default** branch.
4. Create 3 GitHub Environments (`QA`, `Sandbox`, `Production`) and
   populate their variables (`BUCKET_NAME`, `S3_PUBLIC_HOST`,
   `AWS_REGION`, `PUBLIC_REPO`).
5. Org-level secrets (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` /
   `GHB_PAT_TOKEN`) must already be visible to this repo.
6. Verify the `GHB_PAT_TOKEN` owner is in the Bypass list of the public
   repo's `main` branch ruleset **and** `*.*.*` tag ruleset.
7. Smoke-test by pushing a no-op commit to `develop` and watching
   `Actions → Deploy iOS SDK → QA` run end-to-end.

`COCOAPODS_TRUNK_TOKEN` is **not required for v1** — CocoaPods
publication is deferred (see `docs/RELEASE.md §CocoaPods (deferred)`).
When re-enabled, it becomes a repo-level secret, not an org secret
(only the main-branch step reads it).
