#!/usr/bin/env bash
#
# Refuses a release whose version is lower than the newest release already tagged, and exits 1 with a reason.
#
#   .github/scripts/release-newer.sh <version>
#
# Reads the tags of the repository it runs in. A release tag is <major>.<minor>.<patch> and nothing else, so a
# tag of any other shape is not compared. The newest release's own version passes, because whether that tag is
# this release resumed is the existing-tag check's to decide. The publish job runs the same comparison
# again, from the lines below, so they change together.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: release-newer.sh <version>" >&2
    exit 2
fi

VERSION="$1"
release='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if ! [[ "$VERSION" =~ $release ]]; then
    echo "error: '$VERSION' is not <major>.<minor>.<patch>" >&2
    exit 1
fi

# for-each-ref rather than `git tag`, whose output a formatting setting can change. Read on its own, so a
# failure to list the tags stops the script rather than reading as no releases. `sort -V` compares each
# component as a number of any length.
tags="$(git for-each-ref --format='%(refname:strip=2)' refs/tags)"
newest="$(printf '%s\n' "$tags" | { grep -E "$release" || true; } | sort -V | tail -n 1)"
if [ -n "$newest" ] && [ "$(printf '%s\n%s\n' "$newest" "$VERSION" | sort -V | tail -n 1)" != "$VERSION" ]; then
    echo "error: the newest release is $newest, and $VERSION is lower" >&2
    exit 1
fi
echo "newest release: ${newest:-none}"
