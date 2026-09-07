#!/usr/bin/env bash
#
# Prints the `-skip-testing:` arguments for the hardware-only tier, read from
# `.github/hardware-only-tests.txt`, or nothing when that list is empty.
#
#   xcodebuild test -scheme PayabliSDK-Package $(.github/scripts/hardware-only-skips.sh) ...
#
# The output is a list of arguments and has to split into several, which is safe because a test identifier
# carries no whitespace. That is checked below rather than assumed. An empty list produces no output, which
# is the state this is meant to survive.
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
    # The edges only. Deleting interior whitespace would join two identifiers into a third that names no
    # test: xcodebuild would then exclude nothing, and this would exit 0 having reported success. Measured
    # before this changed, `Target/Class/methodA<tab>methodB` came out as `Target/Class/methodAmethodB`.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [ -z "$line" ]; then
        continue
    fi
    case "$line" in
        *[[:space:]]*)
            echo "error: hardware-only entry '$line' contains whitespace; a test identifier has none" >&2
            exit 1
            ;;
    esac
    printf ' -skip-testing:%s' "$line"
done < "$list"
