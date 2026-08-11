#!/usr/bin/env bash
#
# Converts an .xcresult coverage report into SonarQube's generic test coverage
# format, which is what `sonar.coverageReportPaths` reads.
#
#   ./Scripts/xccov-to-sonarqube-generic.sh TestResults.xcresult > coverage.xml
#
# Adapted from SonarSource's reference script for Xcode projects. Nothing else
# reads xccov, so a change to Xcode's output shows up here first: the script
# exits non-zero if it produced no <file> element, rather than handing Sonar an
# empty report that reads as zero coverage.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

function convert_file {
    local xccovarchive_file="$1"
    local file_name="$2"
    local xccov_options="$3"

    # Relative to the repo root, so the report survives being written in one CI
    # job and read in another.
    local relative_name="${file_name#"$REPO_ROOT"/}"

    echo "  <file path=\"$relative_name\">"
    xcrun xccov view $xccov_options --file "$file_name" "$xccovarchive_file" \
        | sed -n '
        s/^ *\([0-9][0-9]*\): *0.*$/    <lineToCover lineNumber="\1" covered="false"\/>/p;
        s/^ *\([0-9][0-9]*\): *[1-9].*$/    <lineToCover lineNumber="\1" covered="true"\/>/p
        '
    echo '  </file>'
}

function xccov_to_generic {
    local files=0
    echo '<coverage version="1">'
    for xcresult in "$@"; do
        local xccov_options=""
        if [[ $xcresult == *".xcresult"* ]]; then
            xccov_options="--archive"
        fi
        while read -r file_name; do
            [ -z "$file_name" ] && continue
            convert_file "$xcresult" "$file_name" "$xccov_options"
            files=$((files + 1))
        done < <(xcrun xccov view $xccov_options --file-list "$xcresult")
    done
    echo '</coverage>'

    if [ "$files" -eq 0 ]; then
        echo "error: no covered files found in $*" >&2
        return 1
    fi
}

if [ $# -eq 0 ]; then
    echo "usage: $0 <path-to-.xcresult> [...]" >&2
    exit 2
fi

xccov_to_generic "$@"
