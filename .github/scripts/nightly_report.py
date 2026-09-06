#!/usr/bin/env python3
"""Collect the nightly's own results into a verdict, a job summary, and a facts file for the Slack poster.

The counterpart of `.github/scripts/nightly_report.py` in `payabli/sdk-android`, and it writes the same
facts schema so both platforms render identically in one channel. The collector itself is not a port: that
one parses JUnit XML written by Gradle, and there is no JUnit XML here. The source is the `.xcresult`
bundle, read through `xcrun xcresulttool`, which ships with Xcode.

Runs in the test job, and must. The result bundles are here and so is the full git history the culprit
lookup needs. It holds no credential, which is what lets it live in the job that runs the tests.

Three outputs, and each has a different reader:

  * the facts file named on the command line, which crosses a job boundary to the poster
  * markdown appended to $GITHUB_STEP_SUMMARY, which is where the failure text lives and what Slack links
  * `verdict=green|red` appended to $GITHUB_OUTPUT, which the workflow's suite gate reads

The verdict is published as a step output rather than left in the facts file because the gate reads it, and
computing it anywhere but the job the gate lives in is how a run and its notification start disagreeing.
Step outcomes alone cannot see a suite that succeeded while discovering no tests, which is the failure this
exists to catch.

Standard library only, and not a GitHub Action: a script has no runtime to deprecate and nothing to pin.
"""

from __future__ import annotations

import html
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# The first line of a failure message, which is what the Slack thread shows. The rest is in the job summary.
MAX_DETAIL_CHARS = 300
MAX_TRACE_CHARS = 4000
# GitHub caps a job summary at 1 MiB. Spent in bytes rather than characters because that cap is a byte
# limit, and 900,000 characters of multi-byte UTF-8 is several times that. Not hypothetical: the storage
# suites deliberately carry non-BMP and malformed text.
MAX_SUMMARY_BYTES = 900_000
# Only the failures the report can list get a git lookup, since attributing one nobody will read costs two
# globs and two `git log` calls. Must stay equal to MAX_LISTED_FAILURES in nightly_slack.py.
MAX_ATTRIBUTED_FAILURES = 12

# The shipped modules, and only those. `xccov` also reports every test bundle, the vendored card-reader
# source, and the two umbrella products that re-expose these same sources; reporting those would double-count
# the same lines and bury the four numbers worth reading. This is the same set `sonar-project.properties`
# measures, minus the fixtures package it excludes from coverage for the same reason.
COVERAGE_TARGETS = (
    "PayabliSDKCore",
    "PayabliSDKPayInPaymentFlow",
    "PayabliSDKTapToPay",
    "PayabliSDKTelemetry",
)

# Where a Swift type might be declared. Ordered widest first only for readability; the lookup requires a
# unique match across all three, so the order does not decide anything.
SOURCE_ROOTS = ("Sources", "Tests", "Example")


class Failure:
    def __init__(self, suite: str, case: str, detail: str, trace: str, kind: str) -> None:
        self.suite = suite
        self.case = case
        self.detail = detail
        self.trace = trace
        self.kind = kind
        # Filled in by attribute(), because the git lookups need a repository and this class does not.
        self.culprits: list[dict[str, str]] = []

    @property
    def label(self) -> str:
        return f"{self.suite} > {self.case}"

    def as_facts(self) -> dict:
        # The trace is deliberately absent. It goes to the job summary and stays in GitHub; the report links
        # it rather than carrying it. That keeps test output out of Slack storage, keeps the thread reply
        # inside Slack's 3000-character block limit, and means the poster never handles failure text beyond
        # one escaped line.
        return {
            "suite": self.suite,
            "case": self.case,
            "label": self.label,
            "detail": self.detail,
            "kind": self.kind,
            "culprits": self.culprits,
        }


def xcresult(bundle: Path, *subcommand: str) -> dict | None:
    """One `xcresulttool` read, or None when the bundle cannot be read.

    Bounded, because every command in this repository is. A bundle that xcresulttool cannot parse is
    reported as unreadable rather than as an empty suite: those are different, and conflating them turns a
    truncated bundle into a silent pass.
    """
    try:
        result = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", *subcommand, "--path", str(bundle)],
            capture_output=True, text=True, timeout=300, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def parse_bundle(bundle: Path) -> tuple[int, int, int, list[Failure]]:
    """Counts and failures from one `.xcresult`.

    Counts come from the `summary` subcommand and failures from the `tests` tree, which is not redundancy.
    `summary` is the only place that reports skipped and expected-failure counts as numbers; the tree is the
    only place that carries a failure message per test, and a test can carry several.

    `totalTestCount` counts skipped cases, so passed has to be derived rather than read. A suite with one
    pass and one skip would otherwise read as "all 2 passed" and then contradict itself by appending the
    skip count.

    A skipped test also carries a Failure Message node, holding its skip reason, so a walk that collects
    every Failure Message reports skips as failures. Only a Test Case whose own result is `Failed`
    contributes here.
    """
    # A bundle that is absent and one that xcresulttool cannot parse are reported the same way, as no
    # results. They are the same thing to a reader: neither carries evidence that anything ran, and the
    # caller turns a zero total under a successful step into a red verdict either way.
    if not bundle.exists():
        return 0, 0, 0, []

    summary = xcresult(bundle, "summary")
    if summary is None:
        return 0, 0, 0, []

    total = summary.get("totalTestCount") or 0
    # Expected failures passed, so they are not failures; they are counted separately by xcresulttool and
    # already excluded from failedTests.
    failed = summary.get("failedTests") or 0
    skipped = summary.get("skippedTests") or 0

    failures: list[Failure] = []
    tree = xcresult(bundle, "tests")
    if tree is None:
        # Counts without detail. Reported rather than dropped, because the numbers still decide the verdict
        # and a red count with no names is more useful than silence.
        return int(total), int(failed), int(skipped), failures

    def walk(nodes: list[dict], suite: str = "") -> None:
        for node in nodes:
            kind = node.get("nodeType")
            name = node.get("name", "")
            children = node.get("children") or []
            if kind == "Test Suite":
                walk(children, name)
                continue
            if kind == "Test Case" and node.get("result") == "Failed":
                messages = [
                    child.get("name", "")
                    for child in children
                    if child.get("nodeType") == "Failure Message"
                ]
                raw = "\n".join(m for m in messages if m)
                failures.append(
                    Failure(
                        suite=suite or node.get("name", ""),
                        case=name,
                        detail=(raw.splitlines()[0] if raw else "(no failure message recorded)")[
                            :MAX_DETAIL_CHARS
                        ],
                        trace=raw,
                        kind="failure",
                    )
                )
                continue
            walk(children, suite)

    walk(tree.get("testNodes") or [])
    return int(total), int(failed), int(skipped), failures


def coverage(bundle: Path) -> list[tuple[str, float | None, str]]:
    """Line coverage per shipped module, from the same bundle the suite wrote.

    One row per module in COVERAGE_TARGETS, always, with a state that distinguishes three answers that must
    not be conflated:

      * `measured` carries a percentage
      * `empty` is a module with no executable lines at all, which is different from 0%
      * `missing` is no readable report, which is what a failed or skipped suite leaves behind

    Every module is named in every case. Reporting only what is on disk lets a module disappear on the
    nights the report matters most, and a silent omission reads as "this module is not measured" rather than
    "this module was not measured tonight".

    Only line coverage exists here. `xccov` reports covered and executable lines and no branch counter, so
    unlike the Android side there is one coverage group rather than two, and the `inapplicable` state the
    facts schema allows is never produced.
    """
    report: dict | None = None
    if bundle.exists():
        try:
            result = subprocess.run(
                ["xcrun", "xccov", "view", "--report", "--json", str(bundle)],
                capture_output=True, text=True, timeout=300, check=False,
            )
            if result.returncode == 0 and result.stdout.strip():
                report = json.loads(result.stdout)
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
            report = None

    measured = {}
    for target in (report or {}).get("targets") or []:
        name = str(target.get("name", ""))
        # `.framework` and similar suffixes appear on some build products; the target name is what the
        # report is keyed on here, so match on the stem rather than requiring an exact string.
        measured[name.split(".", 1)[0]] = target

    out: list[tuple[str, float | None, str]] = []
    for name in COVERAGE_TARGETS:
        target = measured.get(name)
        if target is None:
            out.append((name, None, "missing"))
            continue
        executable = target.get("executableLines") or 0
        if not executable:
            out.append((name, None, "empty"))
            continue
        fraction = target.get("lineCoverage")
        if not isinstance(fraction, (int, float)):
            out.append((name, None, "missing"))
            continue
        out.append((name, 100.0 * float(fraction), "measured"))
    return out


def git_one_line(*args: str) -> str:
    try:
        result = subprocess.run(
            ["git", *args], cwd=REPO_ROOT, capture_output=True, text=True, timeout=20, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""


# Memoised because a broken shared fixture fails many tests in one class, and every one of them would
# otherwise repeat the same glob and the same `git log`. Keyed on the arguments, cleared by process exit.
_SOURCE_CACHE: dict[str, Path | None] = {}
_COMMIT_CACHE: dict[str, dict[str, str] | None] = {}


def last_commit(path: Path) -> dict[str, str] | None:
    """Cached wrapper: the same file is named by every failure in the same class."""
    key = str(path)
    if key not in _COMMIT_CACHE:
        _COMMIT_CACHE[key] = _last_commit_uncached(path)
    return _COMMIT_CACHE[key]


def _last_commit_uncached(path: Path) -> dict[str, str] | None:
    """The last commit to touch a path, as fields rather than a rendered line.

    Unit-separated rather than space-separated, because a commit subject and an author name can both contain
    anything. Splitting a pretty-printed line on spaces would take the first word of a subject as an email
    often enough to matter.
    """
    line = git_one_line("log", "-1", "--format=%h%x1f%an%x1f%ae%x1f%s", "--", str(path))
    if not line:
        return None
    parts = line.split("\x1f")
    if len(parts) != 4:
        return None
    sha, author, email, subject = parts
    return {"sha": sha, "author": author, "email": email, "subject": subject}


def find_source(type_name: str) -> Path | None:
    """The file declaring a Swift type, or None when the answer would be a guess.

    Swift carries no package qualifier, so a filename is the only handle and it has to be unique across the
    whole tree. Several matches means the name alone cannot identify the file, and the honest answer is
    none: naming the wrong file attributes a failure to whoever last touched an unrelated type, beside their
    name, at 3am.

    Filename rather than declaration search on purpose. This repository names a file after the type it
    declares, and grepping for `class <name>` would match an extension, a comment or a test double as
    readily as the declaration.
    """
    if type_name in _SOURCE_CACHE:
        return _SOURCE_CACHE[type_name]
    matches = sorted(
        path
        for root in SOURCE_ROOTS
        for path in (REPO_ROOT / root).glob(f"**/{type_name}.swift")
    )
    found = matches[0].relative_to(REPO_ROOT) if len(matches) == 1 else None
    _SOURCE_CACHE[type_name] = found
    return found


def attribute(failure: Failure) -> None:
    """Attach the last commit to touch the failing test, and the last to touch the type it names.

    A heuristic and labelled as one wherever it is rendered. It is right often enough to start from and
    cheap enough to be worth printing; it is not evidence, and the run log is linked for that. The author
    travels with it because a name beside a commit is the cheapest route to the person who knows.

    The poster is what stops this naming somebody unfairly: a commit that was already in the tree the last
    time the suite was green is reported as unchanged rather than as a culprit.
    """
    test_file = find_source(failure.suite)
    if test_file:
        commit = last_commit(test_file)
        if commit:
            failure.culprits.append({**commit, "what": "test"})

    # PayabliSessionTests -> PayabliSession, KeychainOnDeviceTests -> Keychain. The suffixes are the naming
    # convention this repository uses for a test class and for the hardware tier.
    subject = re.sub(r"(OnDevice)?Tests?$", "", failure.suite)
    if subject and subject != failure.suite:
        subject_file = find_source(subject)
        if subject_file:
            commit = last_commit(subject_file)
            if commit:
                failure.culprits.append({**commit, "what": subject})


def suite_label(failed: int, skipped: int, total: int, outcome: str, missing: bool) -> str:
    """A suite line that never overstates what passed.

    `totalTestCount` counts skipped cases, so passed is derived. A suite with one pass and one skip would
    otherwise read as "all 2 passed" and then contradict itself by appending the skip count.
    """
    if outcome != "success":
        # Names the step state rather than a count, because a count from a step that did not finish
        # describes whatever it managed before dying.
        return f"step {outcome}" + (f", {failed} failed so far" if failed else "")
    if missing:
        return "no results written"
    passed = max(total - failed - skipped, 0)
    parts = []
    if failed:
        parts.append(f"{failed} failed")
    parts.append(f"{passed} passed" if failed or skipped else f"all {passed} passed")
    if skipped:
        parts.append(f"{skipped} skipped")
    return ", ".join(parts) + (f" / {total} tests" if failed or skipped else "")


def build_label(builds: list[tuple[str, str]]) -> str:
    """One line for the build-only steps, naming whichever did not build.

    The nightly builds four things the pull-request gate cannot, and none of them produces a test result.
    Reported together because on almost every night the answer is the same word for all four, and four lines
    saying it separately push the counts that change off the first screen.
    """
    bad = [name for name, outcome in builds if outcome != "success"]
    built = len(builds) - len(bad)
    if not bad:
        return "all built"
    return ", ".join(bad) + " failed" + (f", {built} built" if built else "")


def _utf8_len(text: str) -> int:
    """Byte length, because every limit this file spends against is a byte limit."""
    return len(text.encode("utf-8"))


def clip_trace(trace: str) -> str:
    """Bound a failure message, keeping both ends rather than the first N characters.

    XCTest puts the assertion on the first line and any subsequent recorded failures after it, so a test
    that records several loses the later ones to head-only truncation. Keep two thirds from the top, which
    carries the first assertion and its file and line, and the remainder from the bottom.

    The notice says where the unabridged text is rather than only that trimming happened, since the result
    bundle in the nightly-results artifact always holds it.
    """
    if len(trace) <= MAX_TRACE_CHARS:
        return trace
    head = MAX_TRACE_CHARS * 2 // 3
    tail = MAX_TRACE_CHARS - head
    omitted = len(trace) - MAX_TRACE_CHARS
    return (
        trace[:head]
        + f"\n\n... {omitted} characters trimmed from the middle. The complete text is in the "
        "nightly-results artifact ...\n\n"
        + trace[-tail:]
    )


def write_step_summary(failures: list[Failure]) -> None:
    """Render the failure text into the job summary, which is what the Slack report links at.

    Chosen over the alternatives for a reason each. The results artifact holds the same text but costs the
    reader a download and an unzip. A Slack file upload reads best but needs an upload scope and puts test
    output into Slack storage, which is worth avoiding for a payments SDK even though a failure message
    should carry nothing sensitive. And a per-log-line anchor rots silently, because line numbers move with
    any change to the log.

    Every message is HTML-escaped inside a <pre>, so nothing in test output can close the element and inject
    markup into the summary. A fenced code block would not do: a message containing a fence would escape it.
    """
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if not target or not failures:
        return

    header = (
        f"## Nightly failures ({len(failures)})\n\n"
        "Failure messages, trimmed in the middle where they are long. The complete result bundles are in "
        "the `nightly-results` artifact on this run.\n\n"
    )
    chunks = [header]
    # Spent in bytes, and the header and the worst-case omission notice are charged up front so the notice
    # cannot itself be what pushes the summary over.
    notice_reserve = _utf8_len(f"_{len(failures)} further message(s) omitted: the job summary limit._\n")
    budget = MAX_SUMMARY_BYTES - _utf8_len(header) - notice_reserve
    written = 0
    for failure in failures:
        trace = clip_trace(failure.trace or failure.detail or "(no failure message recorded)")
        # `open` on the first few only. A red night is usually one or two failures and expanding each one by
        # hand is friction; twenty open messages is a wall.
        opened = " open" if written < 3 else ""
        block = (
            f"<details{opened}><summary><code>{html.escape(failure.label)}</code></summary>\n\n"
            f"<pre>{html.escape(trace)}</pre>\n\n</details>\n\n"
        )
        cost = _utf8_len(block)
        if cost > budget:
            chunks.append(f"_{len(failures) - written} further message(s) omitted: the job summary limit._\n")
            break
        budget -= cost
        written += 1
        chunks.append(block)

    try:
        with open(target, "a", encoding="utf-8") as handle:
            handle.write("".join(chunks))
    except OSError as error:
        # A summary that cannot be written must not cost the run its report. The Slack link will point at a
        # run page without a failures section, which is a degraded report rather than a missing one.
        print(f"::warning::Could not write the job summary: {error}", file=sys.stderr)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <facts-output-path>", file=sys.stderr)
        return 2
    facts_path = Path(sys.argv[1])

    # Defaulted so a hand run in a checkout that has just run the suites works with no environment at all.
    sdk_bundle = Path(os.environ.get("SDK_RESULTS", "SDKTests.xcresult"))
    flow_bundle = Path(os.environ.get("FLOW_RESULTS", "DemoFlowTests.xcresult"))

    sdk_total, sdk_failed, sdk_skipped, sdk_details = parse_bundle(sdk_bundle)
    flow_total, flow_failed, flow_skipped, flow_details = parse_bundle(flow_bundle)

    # Set by the workflow from the earlier steps' outcomes, so a step that never ran is not read as a pass.
    sdk_step = os.environ.get("SDK_OUTCOME", "unknown")
    flow_step = os.environ.get("FLOW_OUTCOME", "unknown")
    builds = [
        ("demo app", os.environ.get("APP_BUILD_OUTCOME", "unknown")),
        ("device compile", os.environ.get("DEVICE_COMPILE_OUTCOME", "unknown")),
        ("live bundles", os.environ.get("LIVE_BUNDLES_OUTCOME", "unknown")),
        ("XCFramework", os.environ.get("XCFRAMEWORK_OUTCOME", "unknown")),
    ]

    # Only `success` is green. Everything else, `skipped` included, is red: no step in this workflow has an
    # intentional skip condition, so the only way one is skipped is that something before it failed.
    steps_bad = sdk_step != "success" or flow_step != "success"
    builds_bad = any(outcome != "success" for _, outcome in builds)

    # A green claim also requires results to exist, per suite rather than in total. Checking the sum would
    # let a suite that wrote nothing hide behind one that did, and report "all 0 passed" as a pass, which is
    # the exact regression this nightly exists to catch.
    sdk_missing = sdk_step == "success" and sdk_total == 0
    flow_missing = flow_step == "success" and flow_total == 0

    red = (
        bool(sdk_failed or flow_failed)
        or steps_bad
        or builds_bad
        or sdk_missing
        or flow_missing
    )

    # Named by the workflow rather than inferred from the repo. Both platform SDKs report into the same
    # channel, and a copy of this script that guesses would eventually guess wrong.
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    platform = os.environ.get("PLATFORM", "").strip() or (repo.rsplit("/", 1)[-1] if repo else "Nightly")

    suites = [
        ("SDK", suite_label(sdk_failed, sdk_skipped, sdk_total, sdk_step, sdk_missing)),
        ("Sample app", suite_label(flow_failed, flow_skipped, flow_total, flow_step, flow_missing)),
        ("Builds", build_label(builds)),
    ]

    all_failures = sdk_details + flow_details
    # Only the failures the report can list. See MAX_ATTRIBUTED_FAILURES.
    for failure in all_failures[:MAX_ATTRIBUTED_FAILURES]:
        attribute(failure)

    write_step_summary(all_failures)

    facts = {
        # Bumped whenever a consumer would misread an older file. The poster refuses an unknown version
        # rather than rendering half a message from fields it does not recognise. The number tracks the
        # Android collector's, because both feed the same reader.
        "schema": 4,
        "verdict": "red" if red else "green",
        "platform": platform,
        "suites": [{"name": name, "label": label} for name, label in suites],
        "coverage": [
            {
                "label": "line",
                "modules": [
                    {"module": name, "percent": percent, "state": state}
                    for name, percent, state in coverage(sdk_bundle)
                ],
            }
        ],
        "failures": [failure.as_facts() for failure in all_failures],
    }
    facts_path.parent.mkdir(parents=True, exist_ok=True)
    facts_path.write_text(json.dumps(facts, indent=2), encoding="utf-8")

    # Publish the verdict so the workflow gate can honour it. Step outcomes alone cannot see a suite that
    # succeeded while discovering no tests, so without this the run could stay green while the report said
    # red. The run and the notification must not be able to disagree.
    step_output = os.environ.get("GITHUB_OUTPUT")
    if step_output:
        with open(step_output, "a", encoding="utf-8") as handle:
            handle.write(f"verdict={'red' if red else 'green'}\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
