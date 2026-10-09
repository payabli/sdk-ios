#!/usr/bin/env bash
#
# Refuses a release whose version is lower than the newest release already tagged, and exits 1 with a reason.
#
#   .github/scripts/release-newer.sh <version>
#
# Reads the tags of the repository it runs in. A release tag is <major>.<minor>.<patch> and nothing else, so a
# tag of any other shape is not compared. The newest release's own version passes, because whether that tag is
# this release resumed is the existing-tag check's to decide.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: release-newer.sh <version>" >&2
    exit 2
fi

version="$1"
release='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if ! [[ "$version" =~ $release ]]; then
    echo "error: '$version' is not <major>.<minor>.<patch>" >&2
    exit 1
fi

# True when the first version is lower than the second. Components carry no leading zero, so each compares
# as a number.
lower() {
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<< "$1"
    IFS=. read -r b1 b2 b3 <<< "$2"
    (( a1 < b1 || (a1 == b1 && (a2 < b2 || (a2 == b2 && a3 < b3))) ))
}

# Read before the loop, so a failure to list the tags stops the script rather than reading as no releases.
tags="$(git tag --list)"
newest=""
while IFS= read -r tag; do
    [[ "$tag" =~ $release ]] || continue
    if [ -z "$newest" ] || lower "$newest" "$tag"; then
        newest="$tag"
    fi
done <<< "$tags"

if [ -n "$newest" ] && lower "$version" "$newest"; then
    echo "error: the newest release is $newest, and $version is lower" >&2
    exit 1
fi
echo "newest release: ${newest:-none}"
