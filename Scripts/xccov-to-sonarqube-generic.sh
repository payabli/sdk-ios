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
# One `xccov view --archive --json` call per bundle returns every file's line
# table at once. SonarSource's reference script instead runs `--file-list` and
# then `--file` per file, which is one process per source file and took 117s of
# the CI job for a report this size.
#
# Nothing else reads xccov, so a change to Xcode's output shows up here first:
# the script exits non-zero unless it emitted at least one <lineToCover>, rather
# than handing Sonar a report that reads as zero coverage. Counting files rather
# than lines would not catch it — a per-line format change leaves the file list
# intact and every <file> element empty.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
INCLUDE=()

while [ $# -gt 0 ]; do
    case "$1" in
        --include)
            [ $# -ge 2 ] || { echo "error: --include needs a prefix" >&2; exit 2; }
            INCLUDE+=("$2"); shift 2 ;;
        *) break ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "usage: $0 [--include <prefix>]... <path-to-.xcresult> [...]" >&2
    exit 2
fi

# Newline-separated, because a prefix is a path and the array may be empty.
INCLUDE_PREFIXES=""
if [ ${#INCLUDE[@]} -gt 0 ]; then
    INCLUDE_PREFIXES="$(printf '%s\n' "${INCLUDE[@]}")"
fi
export INCLUDE_PREFIXES

exec python3 - "$@" <<'PY'
import json
import os
import subprocess
import sys
from xml.sax.saxutils import quoteattr

repo_root = os.environ["REPO_ROOT"]
prefixes = [p for p in os.environ.get("INCLUDE_PREFIXES", "").split("\n") if p]


def included(path):
    # No --include keeps everything, so the script stays usable on its own.
    return not prefixes or any(path.startswith(p) for p in prefixes)


# path -> {line number: covered}. Merged across bundles, so a line a second
# suite reached is covered even where the first never entered it.
coverage = {}

for bundle in sys.argv[1:]:
    options = ["--archive"] if ".xcresult" in bundle else []
    # xccov's own message says which bundle and why, and it goes to a captured
    # stderr, so it is reported rather than replaced by a traceback.
    result = subprocess.run(
        ["xcrun", "xccov", "view", *options, "--json", bundle],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        sys.exit(f"error: xccov could not read {bundle}")
    report = json.loads(result.stdout)

    # xccov keys the archive report by absolute file path. Anything else is a
    # format this script has not been read against, and guessing at it is how a
    # report comes back empty but successful.
    if not isinstance(report, dict) or not all(isinstance(v, list) for v in report.values()):
        sys.exit(f"error: unexpected xccov --json shape from {bundle}")

    for absolute, lines in report.items():
        relative = absolute[len(repo_root) + 1:] if absolute.startswith(repo_root + "/") else absolute
        if not included(relative):
            continue
        file_lines = coverage.setdefault(relative, {})
        for line in lines:
            if not line.get("isExecutable"):
                continue
            covered = line.get("executionCount", 0) > 0
            number = line["line"]
            file_lines[number] = file_lines.get(number, False) or covered

emitted = 0
out = sys.stdout
out.write('<coverage version="1">\n')
for path in sorted(coverage):
    lines = coverage[path]
    # A file with nothing coverable contributes no element. Emitting an empty
    # <file> would still count toward a file-based guard.
    if not lines:
        continue
    out.write(f"  <file path={quoteattr(path)}>\n")
    for number in sorted(lines):
        covered = "true" if lines[number] else "false"
        out.write(f'    <lineToCover lineNumber="{number}" covered="{covered}"/>\n')
        emitted += 1
    out.write("  </file>\n")
out.write("</coverage>\n")

if emitted == 0:
    sys.exit(f"error: no coverable lines parsed from {' '.join(sys.argv[1:])} after --include filtering")
PY
