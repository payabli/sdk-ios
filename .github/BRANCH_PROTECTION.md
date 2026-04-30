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

### Tag protection

- All release tags (`*.*.*`, `*.*.*-qa`, `*.*.*-beta`) are created by the
  release workflow using `GITHUB_TOKEN`. Humans do **not** push tags
  manually. Optional hardening: a tag protection rule blocking any non-bot
  identity from creating/deleting those tag patterns.

## Public repo (`payabli/payabli-sdk-ios`) — distribution mirror

Only has `main`:

- **Require a pull request before merging:** no. The only writer is the
  release bot using `PUBLIC_REPO_PAT`. The PAT owner is in the
  push-allowed set; all other identities are blocked.
- **Restrict who can push:** the single service account holding the PAT.
- **Require status checks:** `validate.yml` (`swift package resolve`
  against the manifest) must pass after each release bot push. This
  catches checksum-mismatch or bad URLs before a partner tries to
  consume the tag.
- **Allow force pushes:** disabled.
- **Allow deletions:** disabled.
- **Tag protection:** only the release bot identity can create/delete
  release tags. All tags are immutable once created.

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
5. Org-level secrets (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)
   must already be visible to this repo.
6. Smoke-test by pushing a no-op commit to `develop` and watching
   `Actions → Deploy iOS SDK → QA` run end-to-end.
