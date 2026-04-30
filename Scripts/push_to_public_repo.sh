#!/usr/bin/env bash
#
# push_to_public_repo.sh
# ----------------------
# Clones the public distribution repo, applies the rendered manifests from
# build/public/, commits, pushes, tags, and creates the GitHub Release.
#
# Environment (required):
#   VERSION              e.g. 1.0.247 or 1.0.247-beta
#   PUBLIC_REPO          GitHub slug, e.g. payabli/payabli-sdk-ios
#   PUBLIC_REPO_PAT      GitHub token with write access to the public repo
#                        (sourced from the GHB_PAT_TOKEN GitHub secret in CI)
#
# Optional:
#   GH_ACTOR             commit author name (defaults to "Payabli Release Bot")
#   GH_EMAIL             commit author email (defaults to releases@payabli.com)
#   PUBLIC_BRANCH        branch to push to (defaults to `main`)
#
# Preconditions:
#   - build/public/{Package.swift,PayabliSDK.podspec,README.md} exist (produced
#     by Scripts/render_public_manifests.sh).
#   - `gh` CLI available and authenticated with $PUBLIC_REPO_PAT for the
#     `gh release create` step. The `git` operations use the PAT embedded
#     in the clone URL.

set -euo pipefail

for var in VERSION PUBLIC_REPO PUBLIC_REPO_PAT; do
    if [[ -z "${!var:-}" ]]; then
        echo "error: missing required environment variable: $var" >&2
        exit 1
    fi
done

GH_ACTOR="${GH_ACTOR:-Payabli Release Bot}"
GH_EMAIL="${GH_EMAIL:-releases@payabli.com}"
PUBLIC_BRANCH="${PUBLIC_BRANCH:-main}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDERED_DIR="$REPO_ROOT/build/public"

for f in Package.swift PayabliSDK.podspec README.md; do
    if [[ ! -f "$RENDERED_DIR/$f" ]]; then
        echo "error: missing rendered file ${RENDERED_DIR}/${f} — run Scripts/render_public_manifests.sh first" >&2
        exit 1
    fi
done

# Scratch clone of the public repo, auto-cleaned on exit.
SCRATCH_DIR="$(mktemp -d -t payabli-public-push-XXXXXX)"
trap 'rm -rf "$SCRATCH_DIR"' EXIT

echo "[push] cloning ${PUBLIC_REPO}"
# Embed PAT in URL for the HTTPS clone; never logged by git.
git -c advice.detachedHead=false clone --depth=1 \
    "https://x-access-token:${PUBLIC_REPO_PAT}@github.com/${PUBLIC_REPO}.git" \
    "$SCRATCH_DIR/repo"

cd "$SCRATCH_DIR/repo"
git config user.name "$GH_ACTOR"
git config user.email "$GH_EMAIL"

# Ensure we're on the target branch; create it from origin/main if the
# public repo was just bootstrapped with a different default.
if git rev-parse --verify "$PUBLIC_BRANCH" >/dev/null 2>&1; then
    git checkout "$PUBLIC_BRANCH"
else
    git checkout -b "$PUBLIC_BRANCH"
fi

echo "[push] applying rendered manifests"
cp "$RENDERED_DIR/Package.swift"       "Package.swift"
cp "$RENDERED_DIR/PayabliSDK.podspec"  "PayabliSDK.podspec"
cp "$RENDERED_DIR/README.md"           "README.md"

# Keep the attributions file in sync with the rendered one if present.
if [[ -f "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" ]]; then
    cp "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "NOTICE"
fi

# Classify the release channel from the version suffix. Controls whether
# `main` on the public repo advances (Production only) or the commit stays
# orphan and only the tag is pushed (QA / Sandbox).
case "$VERSION" in
    *-qa)    env_label="qa"         ; is_production=false ;;
    *-beta)  env_label="sandbox"    ; is_production=false ;;
    *)       env_label="production" ; is_production=true  ;;
esac

# Always create a local commit so the tag has a stable object to point at,
# even for non-production channels (tags pointing at orphan commits work
# fine — git preserves any commit referenced by a tag regardless of branch
# reachability).
if git diff --quiet && git diff --cached --quiet; then
    # Rare: a workflow_dispatch re-run that somehow produced byte-identical
    # manifests. Still need a commit so the tag can point somewhere new.
    echo "[push] no diff against ${PUBLIC_REPO}@${PUBLIC_BRANCH} — creating empty release commit"
    git commit --allow-empty -m "release: ${VERSION} (${env_label})"
else
    git add -A
    git commit -m "release: ${VERSION} (${env_label})"
fi

# Tags are immutable: fail loudly if we accidentally re-publish the same
# version (monotonic versioning should prevent this, but double-checking
# protects against accidental re-runs of workflow_dispatch).
if git ls-remote --tags origin "refs/tags/${VERSION}" | grep -q "refs/tags/${VERSION}"; then
    echo "error: tag ${VERSION} already exists on ${PUBLIC_REPO}" >&2
    exit 1
fi

echo "[push] tagging ${VERSION}"
git tag -a "$VERSION" -m "PayabliSDK ${VERSION}"

# Push the tag first. `git push` of a tag also uploads any commits it
# references, so the commit with the rendered manifests becomes permanent
# in the remote's object store — reachable by `git checkout <tag>` and by
# SPM resolvers, whether or not it's on any branch.
echo "[push] pushing tag ${VERSION}"
git push origin "refs/tags/${VERSION}"

# Production releases additionally advance `main` so a naked `git clone` of
# the public repo shows the latest GA manifest. QA / Sandbox releases do
# NOT push the branch: `main` stays on the previous production commit, and
# the QA/beta tag lives as an orphan object reachable only by tag name.
if [[ "$is_production" == true ]]; then
    echo "[push] production release — pushing commit to ${PUBLIC_BRANCH}"
    git push origin "$PUBLIC_BRANCH"
else
    echo "[push] ${env_label} release — leaving ${PUBLIC_BRANCH} untouched (tag-only publish)"
fi

# GitHub Release — pre-releases are marked for qa/beta suffixes.
prerelease_flag=""
if [[ "$VERSION" == *-* ]]; then
    prerelease_flag="--prerelease"
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "warning: gh CLI not available; skipping 'gh release create'" >&2
    exit 0
fi

echo "[push] creating GitHub Release"
GH_TOKEN="$PUBLIC_REPO_PAT" gh release create "$VERSION" \
    --repo "$PUBLIC_REPO" \
    --title "PayabliSDK ${VERSION}" \
    --notes "Automated release from the private SDK repo. See the top-level Package.swift for binary URLs and checksums." \
    $prerelease_flag || {
    echo "warning: gh release create failed; the tag was pushed, so the release can be created manually." >&2
}

echo "[push] done."
