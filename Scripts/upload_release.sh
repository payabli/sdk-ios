#!/usr/bin/env bash
#
# upload_release.sh
# -----------------
# Uploads the rendered XCFramework zips (plus the MIT licenses file) from
# build/release/ to the environment-specific S3 bucket.
#
# Environment (required):
#   VERSION           e.g. 1.0.247-qa (used only for logging + dry-run verify)
#   BUCKET_NAME       e.g. payabli-public-objects-qa
#
# Preconditions:
#   - `aws` CLI available and authenticated (creds come from the CI runner's
#     IAM role / env vars; this script does not handle auth).
#   - `build/release/` already populated by Scripts/build_release_frameworks.sh.
#
# Notes:
#   - v1 publishes zips at the **root** of the bucket (no path prefix) because
#     the iOS team does not yet own folder-create permissions on these
#     shared buckets. The filenames are prefixed with `payabli-ios-sdk-` to
#     disambiguate from other assets in the same bucket. Task-24 migrates
#     this to a dedicated `sdk-ios/` folder once DevOps grants permissions.
#   - `--cache-control "public,max-age=31536000,immutable"` lets the public
#     repo keep pointing at an unchanging URL per version (binary releases
#     are immutable by design; a re-release cuts a new patch).

set -euo pipefail

if [[ -z "${VERSION:-}" ]]; then
    echo "error: VERSION environment variable is required" >&2
    exit 1
fi
if [[ -z "${BUCKET_NAME:-}" ]]; then
    echo "error: BUCKET_NAME environment variable is required" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$REPO_ROOT/build/release"

if [[ ! -d "$RELEASE_DIR" ]]; then
    echo "error: ${RELEASE_DIR} not found — run Scripts/build_release_frameworks.sh first" >&2
    exit 1
fi

expected_zips=(
    "payabli-ios-sdk-core-${VERSION}.zip"
    "payabli-ios-sdk-taptopay-${VERSION}.zip"
    "payabli-ios-sdk-payin-payment-flow-${VERSION}.zip"
    "payabli-ios-sdk-card-reader-core-${VERSION}.zip"
)

missing=()
for f in "${expected_zips[@]}"; do
    if [[ ! -f "$RELEASE_DIR/$f" ]]; then
        missing+=("$f")
    fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: release artifacts missing in ${RELEASE_DIR}: ${missing[*]}" >&2
    exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
    echo "error: aws CLI not available on PATH" >&2
    exit 1
fi

echo "[upload] VERSION=${VERSION} BUCKET=${BUCKET_NAME}"

# Sync only the SDK-iOS zips — filename prefix disambiguates from anything
# else already in the bucket.
aws s3 cp "$RELEASE_DIR/" "s3://${BUCKET_NAME}/" \
    --recursive \
    --exclude "*" \
    --include "payabli-ios-sdk-*.zip" \
    --cache-control "public,max-age=31536000,immutable"

# Attach the THIRD_PARTY_LICENSES file once per release so the public repo's
# NOTICE file can link directly to it (versioned for historical accuracy).
if [[ -f "$RELEASE_DIR/THIRD_PARTY_LICENSES.txt" ]]; then
    aws s3 cp "$RELEASE_DIR/THIRD_PARTY_LICENSES.txt" \
        "s3://${BUCKET_NAME}/payabli-ios-sdk-licenses-${VERSION}.txt" \
        --cache-control "public,max-age=31536000,immutable"
fi

echo "[upload] done. Verify:"
for f in "${expected_zips[@]}"; do
    echo "   https://${BUCKET_NAME}.s3.amazonaws.com/${f}"
done
