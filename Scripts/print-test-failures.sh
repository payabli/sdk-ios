#!/usr/bin/env bash
#
# Prints the assertion and its file and line for every failed test in an
# .xcresult bundle.
#
#   ./Scripts/print-test-failures.sh SDKTests.xcresult
#
# `xcodebuild -quiet` names the failing tests and stops there. A name on its own
# sends the reader to a local reproduction to find out what the assertion said,
# which is the part CI already knows. Nothing here is third party: the bundle is
# already written by -resultBundlePath and xcresulttool ships with Xcode.

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "usage: $0 <path-to-.xcresult> [...]" >&2
    exit 2
fi

for bundle in "$@"; do
    if [ ! -e "$bundle" ]; then
        echo "no result bundle at $bundle" >&2
        continue
    fi
    echo "=== $bundle ==="
    xcrun xcresulttool get test-results tests --path "$bundle" | python3 -c '
import json
import sys

report = json.load(sys.stdin)
failures = []


def walk(nodes, test=None, failed=False):
    for node in nodes:
        kind = node.get("nodeType")
        name = node.get("name", "")
        if kind == "Test Case":
            test = name
            # A skip reason is also carried as a Failure Message, and a skipped
            # test is not a failing one.
            failed = node.get("result") == "Failed"
        elif kind == "Failure Message" and failed:
            failures.append((test, name))
        walk(node.get("children") or [], test, failed)


walk(report.get("testNodes") or [])
for test, message in failures:
    label = test or "unknown test"
    print(f"  {label}\n      {message}")
if not failures:
    print("  no failed tests recorded in this bundle")
'
done
