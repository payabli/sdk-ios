#!/usr/bin/env bash
#
# Prints the version a release is tagged under, or refuses with a reason and exits 1.
#
#   .github/scripts/release-version.sh <ref>
#
# Prints the tag on stdout and nothing else. A tag is the publication: a consumer resolves the package by
# it, so the version comes from `PayabliCore.version`, and a release is cut from main only.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: release-version.sh <ref>" >&2
    exit 2
fi

ref="$1"
source_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/Sources/PayabliSDKCore/PayabliSDKCore.swift"

if [ ! -f "$source_file" ]; then
    echo "error: no version source at $source_file" >&2
    exit 1
fi

# The declaration is `public static var version: String {` with the literal alone on the next line, which
# is the shape swiftformat gives it. Any other declaration of `version` in the file, live or in dead code, is
# refused rather than guessed between, since a text read cannot tell which one the compiler sees.
declarations="$(grep -cE '\bstatic[[:space:]]+(var|let)[[:space:]]+version\b' "$source_file" || true)"
if [ "$declarations" -ne 1 ]; then
    echo "error: $source_file declares version $declarations times; it must declare it once" >&2
    exit 1
fi
declared="$(awk '
    /^[[:space:]]*public static var version: String \{[[:space:]]*$/ {
        if ((getline line) > 0 && line ~ /^[[:space:]]*"[^"]*"[[:space:]]*$/) {
            gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", line)
            print line
        }
    }
' "$source_file")"
if [ -z "$declared" ]; then
    echo "error: $source_file does not declare PayabliCore.version as a literal" >&2
    exit 1
fi

if ! [[ "$declared" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: the tree declares '$declared', which is not <major>.<minor>.<patch>" >&2
    exit 1
fi

if [ "$ref" != "refs/heads/main" ]; then
    echo "error: a release is cut from refs/heads/main, not $ref" >&2
    exit 1
fi

echo "$declared"
