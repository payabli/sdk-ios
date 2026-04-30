# Payabli iOS SDK — Release Runbook

This runbook documents the end-to-end release process for the Payabli iOS
SDK. The pipeline is **push-based**: every merge into `develop`, `sandbox`,
or `main` automatically cuts a release to the matching environment. There is
no manual tag/bump step for routine releases.

## Audience

- SDK maintainers cutting a new release or promoting one between tiers.
- DevOps confirming infra prerequisites.
- On-call engineers executing rollbacks or debugging a failed deploy.

## Environments at a glance

| Branch    | GitHub Environment | S3 bucket                         | CDN tag suffix | Audience                             |
|-----------|--------------------|-----------------------------------|----------------|--------------------------------------|
| `develop` | `QA`               | `payabli-public-objects-qa`       | `-qa`          | Internal Payabli engineers, QA, bug-repro partners |
| `sandbox` | `Sandbox`          | `payabli-public-objects-sandbox`  | `-beta`        | Partners opted in to early-access    |
| `main`    | `Production`       | `payabli-public-objects-prod`     | *(none)*       | Partners GA                          |

URL pattern: `https://{BUCKET}.s3.amazonaws.com/payabli-ios-sdk-{core|payin|card-reader-core}-{VERSION}.zip`.

All three tiers publish tags to the **same** public repo
`payabli/payabli-sdk-ios`. Consumers pick a tier by the tag pattern they
resolve (`from: "1.0.0"` = GA only, `exact: "1.0.247-beta"` = sandbox, etc.).

### Public repo branching model

The public distribution repo is tag-driven, not branch-driven:

- **Branches:** only `main`. Consumers should never resolve by branch.
- **Tags:** one per release across all three tiers
  (`1.0.247-qa`, `1.0.248-beta`, `1.0.249`, …). Every tag is immutable
  and carries its own rendered `Package.swift` with the correct S3 bucket.

The `main` branch **only advances on Production releases**. QA and Sandbox
releases create a tag that points at an orphan commit (a commit not on any
branch). Git preserves any object referenced by a tag, so SPM resolvers
resolve these tags correctly — they just aren't reachable from the branch
graph. Net effect: a naked `git clone https://github.com/payabli/payabli-sdk-ios`
always shows the latest GA manifest, not whatever intermediate QA/beta
artifact happened to ship last.

## Promotion flow

```
feature/* -----(PR)-----> develop ------> auto-deploy to QA       (tag 1.0.N-qa)
                             |
                           (PR)
                             v
                          sandbox -------> auto-deploy to Sandbox (tag 1.0.N-beta)
                             |
                           (PR)
                             v
                           main ---------> auto-deploy to Prod    (tag 1.0.N)
```

The same commit will carry different tag suffixes as it moves between
branches (because `git rev-list --count HEAD` grows by 1 with each merge
commit). That's OK — the monotonic patch number is the guarantee SPM cares
about, and SemVer resolvers still treat `1.0.248` as "newer than
`1.0.247-beta`".

## Standard release: new feature from a `feature/*` branch

1. Create a feature branch from `develop` (`git checkout -b feature/my-thing develop`).
2. Implement, write tests, run `swift build && swift test` locally.
3. Open a PR into `develop`; get at least one approving review.
4. Merge. Watch `Actions → Deploy iOS SDK → QA`:
   - `Compute version` writes `VERSION=1.0.N-qa` to `$GITHUB_ENV`.
   - `Build XCFrameworks` produces 3 zips under `build/release/`.
   - `Upload XCFramework zips to S3` pushes them to `payabli-public-objects-qa`.
   - `Render public manifests` and `Push to public repo + tag + release`
     create the matching tag on `payabli/payabli-sdk-ios`.
5. Validate the QA tag: update the internal demo app's
   `.package(url: …, exact: "1.0.N-qa")`, run against `api-qa.payabli.com`.
6. When QA is happy, open **promotion PR** `develop → sandbox`. Merge.
   Watch `Deploy iOS SDK → Sandbox`. The resulting tag is `1.0.(N+1)-beta`
   (new merge commit bumps the count).
7. Notify beta partners. When the beta bake is complete, open **promotion
   PR** `sandbox → main`. Merge. `Deploy iOS SDK → Production` runs and
   the tag `1.0.(N+2)` lands on the public repo.
8. Announce GA.

## Major / minor bump

The `VERSION` file at the repo root is the single source of truth for the
`major.minor` pair. The patch is always derived from `git rev-list --count HEAD`.

To cut `1.1.0`:

1. Open a PR to `develop` that edits `VERSION` from `1.0` → `1.1`.
2. Merge. The first push produces `1.1.N-qa` (the build counter continues
   from where it was). There is no "jump" in the patch number; this is
   intentional — SPM's SemVer resolver compares major/minor first, so
   consumers with `from: "1.0.0"` upgrade to `1.1.N` naturally.
3. Promote through sandbox → main as usual.

## `workflow_dispatch` (manual escape hatch)

Use only when the auto-versioning path can't run cleanly:

- Git history was rewritten and the commit count is no longer monotonic.
- Auto-computed version collides with an already-published tag.
- A hotfix needs to skip the usual promotion flow (prefer this sparingly —
  promotion PRs are the audited path).

```bash
# From Actions → Deploy iOS SDK → Run workflow
# - branch: main (or develop/sandbox)
# - version: 1.0.253-hotfix
# - skip_publish: false

gh workflow run release.yml \
    --ref main \
    -f version=1.0.253-hotfix \
    -f skip_publish=false
```

`skip_publish=true` runs the full test + build path but stops before S3
upload / tag push. Use to verify a commit produces valid artifacts without
exposing anything to partners.

## Rollback

### 1. Software rollback (the shipped version has a bug)

**Forward-only.** Do not delete the bad tag — consumers may have already
resolved it into their `Package.resolved`, and deleting it breaks their
builds.

1. Open a **revert PR** against the environment that went bad
   (`git revert <bad-sha>`, targeting `main` for GA).
2. Merge. A new patch version (`1.0.(N+1)`) is cut automatically with the
   revert applied.
3. Consumers who pin with `from: "1.0.0"` pick up the fix on their next
   `swift package update`. Consumers pinned with `exact:` stay on the
   broken version until they bump manually — notify them via support.

### 2. Manifest rollback (the rendered `Package.swift` is malformed)

If the binaries are fine but the rendered public manifest is broken
(template typo, wrong CDN host, etc.):

1. Revert the bad commit in `payabli/payabli-sdk-ios` directly.
2. The bad **tag** still exists and still points at the bad manifest, so
   re-cut a new patch version to give consumers a working tag.

### 3. Binary rollback (the zip is corrupt)

This is the only case where deleting from S3 is correct:

1. `aws s3 rm s3://${BUCKET_NAME}/payabli-ios-sdk-<product>-<VERSION>.zip`
2. Re-run the release workflow (workflow_dispatch on the same ref).
3. Verify `curl -I` returns 200 on the re-uploaded URL.

Consumers who already downloaded the zip before deletion keep it in their
local SPM cache and are unaffected. Fresh resolves after the re-upload get
the corrected binary — the checksum in `Package.swift` is unchanged because
the re-build is reproducible (SOURCE_DATE_EPOCH pinned to HEAD).

### 4. CocoaPods rollback (GA only)

**N/A for v1.** CocoaPods publication is deferred (see *CocoaPods
(deferred)* below). This section is retained for when Trunk publishing
is re-enabled:

`pod trunk delete PayabliSDK <VERSION>` works within a 30-day window.
After that, the only recourse is to publish a superseding version.

## Troubleshooting

### `checksum mismatch` during `swift package resolve`

- **Cause:** the zip in S3 was re-uploaded with a different
  `SOURCE_DATE_EPOCH`, producing a different sha256.
- **Fix:** the consumer's `Package.resolved` was cached. They either
  bump to a newer patch, or run `swift package reset && swift package resolve`.
- **Prevention:** don't re-upload zips for the same version. Cut a new
  patch (which is trivial — just re-run with a fresh merge).

### `xcodebuild test` fails on `no iPhone simulator available`

- Check the selected Xcode on the runner: `xcodebuild -version`.
- macos-15 GitHub-hosted runners ship a handful of iPhone simulators
  pre-installed; if none are available, re-run the job.

### `push_to_public_repo.sh` fails with `Permission to payabli/payabli-sdk-ios denied`

- The `PUBLIC_REPO_PAT` env var is injected from the org-level
  `GHB_PAT_TOKEN` secret. Verify the token value hasn't expired and
  that the owning GitHub user (whoever created the PAT) is in the
  **Bypass list** of both rulesets on `payabli/payabli-sdk-ios` (the
  `main` branch rule and the `*.*.*` tag rule). The bot cannot push
  if the ruleset blocks its identity.
- Quick check:
  ```bash
  curl -sI -H "Authorization: Bearer $TOKEN" \
    https://api.github.com/repos/payabli/payabli-sdk-ios
  # expect HTTP/2 200
  ```

### `aws s3 cp` fails with `AccessDenied` on the upload step

- Confirm the runner's AWS credentials (`AWS_ACCESS_KEY_ID` /
  `AWS_SECRET_ACCESS_KEY`) have `s3:PutObject` on the
  environment-specific bucket (`payabli-public-objects-{qa,sandbox,prod}`).
- Confirm the GitHub Environment for the branch is correctly mapped
  (`QA`, `Sandbox`, or `Production`) — `BUCKET_NAME` is per-environment.

### `pod trunk push` fails on the main release

**Currently disabled for v1.** See *CocoaPods (deferred)* below.

When re-enabled:

- Trunk is eventually-consistent; propagation can take up to ~2h.
  `pod search PayabliSDK` against the CDN happens only after Trunk
  re-indexes.
- If the workflow step returned a network error, re-run just that job.
  Pushing the same version to Trunk twice is a no-op (the second push
  returns `Version X is already in progress…` and succeeds).

### A version was published that points to a non-existent S3 URL

- Check the rendered `build/public/Package.swift` artifact in the
  release workflow run. The `S3_PUBLIC_HOST` env var should match the
  environment's bucket.
- Re-run the workflow; Scripts/render_public_manifests.sh fails loudly
  if any placeholder is unresolved.

## Verifying a release from scratch

For smoke-testing after major pipeline changes:

```bash
# 1. Fresh checkout of the public mirror.
git clone https://github.com/payabli/payabli-sdk-ios.git /tmp/payabli-test
cd /tmp/payabli-test
git checkout 1.0.247-qa     # or whatever tag you're smoke-testing

# 2. Inspect the rendered manifest.
cat Package.swift

# 3. Verify the advertised binaries exist and have the advertised sha256.
BUCKET="payabli-public-objects-qa.s3.amazonaws.com"
for slug in core payin card-reader-core; do
    url="https://${BUCKET}/payabli-ios-sdk-${slug}-1.0.247-qa.zip"
    curl -sI "$url" | head -n 1     # expect: HTTP/2 200
    remote_sha=$(curl -s "$url" | shasum -a 256 | awk '{print $1}')
    echo "${slug}: ${remote_sha}"   # compare against Package.swift `checksum:` values
done

# 4. Resolve from a scratch app.
mkdir /tmp/smoke && cd /tmp/smoke
swift package init --type executable
# ...add the dependency + swift package resolve...
```

For the full partner-integration smoke test, see
`Example/INTERNAL_APPS_INTEGRATION.md`.

## CocoaPods (deferred)

CocoaPods publication is **disabled for v1**. The pipeline ships via
Swift Package Manager only. All the infrastructure to turn it on later
remains in place in the private repo:

- `.github/templates/public-PayabliSDK.podspec.tmpl` — rendered template.
- `Scripts/render_public_manifests.sh` — renders `PayabliSDK.podspec`
  into `build/public/` every release (catches template regressions).
- `.github/workflows/ci.yml` → `validate-pods` — lints the rendered
  podspec on every PR.
- `Scripts/push_to_public_repo.sh` — copies the rendered podspec into
  the public repo alongside `Package.swift` (dormant file; nothing
  consumes it because the public README no longer advertises CocoaPods).
- `.github/workflows/release.yml` — the `CocoaPods trunk push (main only)`
  step is commented out with a TODO block listing the exact steps to
  re-enable.

### Known gap to fix before flipping on

The current `public-PayabliSDK.podspec.tmpl` assumes a **single combined
XCFramework zip** (`payabli-ios-sdk-${VERSION}.zip`) but
`Scripts/build_release_frameworks.sh` produces three separate zips
(`-core-`, `-payin-`, `-card-reader-core-`). Before enabling the
Trunk push, pick one of:

1. Extend `build_release_frameworks.sh` to emit a 4th combined zip and
   update `upload_release.sh` to push it too; keep the podspec referencing
   the combined zip.
2. Rewrite `public-PayabliSDK.podspec.tmpl` so each subspec has its own
   `vendored_frameworks` entry pointing at its existing per-product zip
   (same URLs SPM already resolves; no repackaging needed).

Option 2 is cleaner — both package managers consume the same S3 objects.

### Re-enable checklist

When DevOps is ready:

1. Have the release maintainer run `pod trunk register releases@payabli.com`
   on their laptop to generate a Trunk session token.
2. Create a repo secret `COCOAPODS_TRUNK_TOKEN` with that token value
   on `payabli/sdk-ios`.
3. Apply one of the two fixes above for the combined-zip gap.
4. Restore the CocoaPods installation section in
   `.github/templates/public-README.md.tmpl`.
5. Uncomment the `CocoaPods trunk push (main only)` step in
   `.github/workflows/release.yml`.
6. Smoke-test with `skip_publish=false` on a hotfix branch before the
   next real `main` release.
