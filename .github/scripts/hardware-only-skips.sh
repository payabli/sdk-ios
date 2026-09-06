#!/usr/bin/env bash
#
# Prints the `-skip-testing:` arguments for the hardware-only tier, read from
# `.github/hardware-only-tests.txt`, or nothing when that list is empty.
#
#   xcodebuild test -scheme PayabliSDK-Package $(.github/scripts/hardware-only-skips.sh) ...
#
# Unquoted on purpose at the call site: the output is a list of arguments and has to split into several.
# A test identifier carries no whitespace, which is what makes that safe, and the list is checked below
# rather than assumed. An empty list expands to nothing, which is the state this is meant to survive.
#
# Its reason for existing is that the same exclusions must apply in the nightly and in the pull-request
# gate. Two copies of the list would be two lists the moment one of them is edited, and the failure is
# silent: a test excluded in one tier and skipping in the other reports a standing skip nobody reads.

set -euo pipefail

list="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hardware-only-tests.txt"

if [ ! -f "$list" ]; then
    echo "error: no hardware-only test list at $list" >&2
    exit 1
fi

# `|| [ -n "$line" ]` so a final line with no trailing newline is still read.
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    # Trims in both directions, and rejects rather than repairs anything with whitespace inside it: an
    # identifier that splits would become two arguments and silently exclude nothing.
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    if [ -z "$line" ]; then
        continue
    fi
    printf ' -skip-testing:%s' "$line"
done < "$list"
