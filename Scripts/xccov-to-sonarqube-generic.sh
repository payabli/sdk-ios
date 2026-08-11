#!/usr/bin/env bash
#
# Converts an .xcresult coverage report into SonarQube's generic test coverage
# format, which is what `sonar.coverageReportPaths` reads.
#
#   ./Scripts/xccov-to-sonarqube-generic.sh TestResults.xcresult > coverage.xml
#   ./Scripts/xccov-to-sonarqube-generic.sh --include Sources/ a.xcresult b.xcresult
#
# `--include` is repeatable and keeps only files under the given repo-relative
# prefixes. A coverage report should describe what the analysis measures: an
# .xcresult also covers the test files themselves and any vendored source the
# suite touched, and handing those to Sonar asks it to reconcile files it holds
# as tests, or does not hold at all.
#
# Adapted from SonarSource's reference script for Xcode projects. Nothing else
# reads xccov, so a change to Xcode's output shows up here first: the script
# exits non-zero unless it emitted at least one <lineToCover>, rather than
# handing Sonar a report that reads as zero coverage. Counting files rather than
# lines would not catch it — a per-line format change leaves the file list intact
# and every <file> element empty.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INCLUDE=()

while [ $# -gt 0 ]; do
    case "$1" in
        --include)
            [ $# -ge 2 ] || { echo "error: --include needs a prefix" >&2; exit 2; }
            INCLUDE+=("$2"); shift 2 ;;
        *) break ;;
    esac
done

# No --include keeps everything, so the script stays usable on its own.
function included {
    [ ${#INCLUDE[@]} -eq 0 ] && return 0
    local path="$1" prefix
    for prefix in "${INCLUDE[@]}"; do
        case "$path" in "$prefix"*) return 0 ;; esac
    done
    return 1
}

# Total <lineToCover> elements emitted, which is what the guard at the end reads.
LINES_EMITTED=0

function convert_file {
    local xccovarchive_file="$1"
    local file_name="$2"
    local xccov_options="$3"

    # Relative to the repo root, so the report survives being written in one CI
    # job and read in another.
    local relative_name="${file_name#"$REPO_ROOT"/}"

    local lines
    lines=$(xcrun xccov view $xccov_options --file "$file_name" "$xccovarchive_file" \
        | sed -n '
        s/^ *\([0-9][0-9]*\): *0.*$/    <lineToCover lineNumber="\1" covered="false"\/>/p;
        s/^ *\([0-9][0-9]*\): *[1-9].*$/    <lineToCover lineNumber="\1" covered="true"\/>/p
        ')

    # A file with nothing coverable contributes no element. Emitting an empty
    # <file> would still count toward a file-based guard.
    [ -n "$lines" ] || return 0

    echo "  <file path=\"$relative_name\">"
    printf '%s\n' "$lines"
    echo '  </file>'
    LINES_EMITTED=$((LINES_EMITTED + $(printf '%s\n' "$lines" | wc -l)))
}

function xccov_to_generic {
    local files=0
    echo '<coverage version="1">'
    for xcresult in "$@"; do
        local xccov_options=""
        if [[ $xcresult == *".xcresult"* ]]; then
            xccov_options="--archive"
        fi
        # Read the list first. In `done < <(...)` the process substitution's
        # status is not the loop's, so an unreadable archive would be skipped in
        # silence and the report would come back short but successful. Declared
        # before assignment because `local x=$(...)` takes the status of
        # `local`, not of the command.
        local file_list
        file_list=$(xcrun xccov view $xccov_options --file-list "$xcresult")

        while read -r file_name; do
            [ -z "$file_name" ] && continue
            included "${file_name#"$REPO_ROOT"/}" || continue
            convert_file "$xcresult" "$file_name" "$xccov_options"
        done <<< "$file_list"
    done
    echo '</coverage>'

    if [ "$LINES_EMITTED" -eq 0 ]; then
        echo "error: no coverable lines parsed from $* after --include filtering" >&2
        return 1
    fi
}

if [ $# -eq 0 ]; then
    echo "usage: $0 [--include <prefix>]... <path-to-.xcresult> [...]" >&2
    exit 2
fi

xccov_to_generic "$@"
