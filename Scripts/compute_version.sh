#!/usr/bin/env bash
#
# compute_version.sh
# ------------------
# Deterministic version derivation for the Payabli iOS SDK release pipeline.
#
# Output: a single `VERSION=<full-version>` line written to stdout, intended
# to be appended to $GITHUB_ENV inside the release workflow.
#
# Scheme:
#   BASE  = contents of the root VERSION file (major.minor, e.g. "1.0")
#   BUILD = git rev-list --count HEAD       (monotonic patch number)
#   SUFFIX derived from the branch:
#       main     → no suffix     → 1.0.247         (production, SemVer stable)
#       sandbox  → -beta         → 1.0.247-beta    (partners early-access)
#       develop  → -qa           → 1.0.247-qa      (internal QA)
#       anything → exit 1                          (branch not mapped to env)
#
# CI picks up the branch via $GITHUB_REF_NAME (set by GitHub Actions). When
# running locally without $GITHUB_REF_NAME, the current git branch is used.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "error: missing $VERSION_FILE" >&2
    exit 1
fi

# Trim whitespace + validate `major.minor` shape (e.g., "1.0" or "2.15").
BASE="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$BASE" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "error: VERSION file must contain a single 'major.minor' string (got: '$BASE')" >&2
    exit 1
fi

# git rev-list --count HEAD is monotonic across the branch history; new
# merges always produce a strictly-greater count, so SPM's SemVer resolver
# always picks the newest tag.
BUILD="$(cd "$REPO_ROOT" && git rev-list --count HEAD)"

BRANCH="${GITHUB_REF_NAME:-}"
if [[ -z "$BRANCH" ]]; then
    BRANCH="$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD)"
fi

case "$BRANCH" in
    main)
        FULL="${BASE}.${BUILD}"
        ;;
    sandbox)
        FULL="${BASE}.${BUILD}-beta"
        ;;
    develop)
        FULL="${BASE}.${BUILD}-qa"
        ;;
    *)
        echo "error: branch '$BRANCH' is not mapped to a release environment (expected one of: develop, sandbox, main)" >&2
        exit 1
        ;;
esac

echo "VERSION=${FULL}"
