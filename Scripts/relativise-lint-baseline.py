#!/usr/bin/env python3
"""Make the SwiftLint baseline's paths relative to the repository root.

`swiftlint --write-baseline` records the absolute path of every violation, which
is the path on the machine that wrote it. A baseline left that way suppresses
nothing anywhere else: matching is by path, so on a CI runner every violation in
it fires and the job fails. It also puts a local directory layout into a public
repository.

Run this after every `--write-baseline`. It is idempotent, and it exits non-zero
when nothing was rewritten and absolute paths remain, so a run that did not do
what it was for is not mistaken for one that did.

    swiftlint --write-baseline .swiftlint-baseline.json
    python3 Scripts/relativise-lint-baseline.py
"""

import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
BASELINE = REPO / ".swiftlint-baseline.json"
PREFIX = "file://" + str(REPO) + "/"


def main() -> int:
    if not BASELINE.exists():
        print("no baseline at %s" % BASELINE, file=sys.stderr)
        return 1

    entries = json.loads(BASELINE.read_text())
    rewritten = 0
    for entry in entries:
        location = entry["violation"]["location"]
        path = location["file"]
        if path.startswith(PREFIX):
            location["file"] = path[len(PREFIX):]
            rewritten += 1

    remaining = [
        entry["violation"]["location"]["file"]
        for entry in entries
        if entry["violation"]["location"]["file"].startswith("file://")
    ]
    if remaining:
        print(
            "absolute paths remain, and they are not this repository's:\n  %s"
            % "\n  ".join(sorted(set(remaining))[:5]),
            file=sys.stderr,
        )
        return 1

    BASELINE.write_text(json.dumps(entries, separators=(",", ":")))
    print("%d of %d entries rewritten; %d already relative"
          % (rewritten, len(entries), len(entries) - rewritten))
    return 0


if __name__ == "__main__":
    sys.exit(main())
