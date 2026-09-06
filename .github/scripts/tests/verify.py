#!/usr/bin/env python3
"""Drive the nightly collector and poster against synthetic inputs, and assert what each must do.

Two halves, exercised two different ways, and neither is arbitrary.

The **collector** runs as a subprocess inside a synthetic git repository. It globs for source files, resolves
paths against its own repository root and shells out to `xcrun`, and none of that is exercised by importing
it: an in-process test would run against this repository's real tree and its real history, which changes
under the test. The `xcrun` it finds is a stub on PATH that reads JSON fixtures out of the fake result
bundle, so the subprocess call, the argument shape, the JSON decode and the failure paths are all real. That
also lets the harness run on a machine with no Xcode, which is what the CI job has.

The **poster** runs in-process against a fake Slack on loopback. It posts twice and the second call depends
on the first one's `ts`, so a stub that returns canned values without being a server would not exercise the
contract that matters. The same server answers the GitHub compare endpoints, which is how the last-green
range is driven.

Every check is named and printed. A run that asserts nothing fails, because a harness that quietly examines
nothing looks exactly like one that passes.

    python3 .github/scripts/tests/verify.py

Environment:
    NIGHTLY_ONLY        collector | poster | workflows | both   (default: both, meaning all three)
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = REPO_ROOT / ".github" / "scripts"
COLLECTOR = SCRIPTS / "nightly_report.py"
POSTER = SCRIPTS / "nightly_slack.py"
NIGHTLY_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "nightly.yml"
SCRIPTS_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "scripts.yml"

HALVES = ("collector", "poster", "workflows", "both")
ONLY = os.environ.get("NIGHTLY_ONLY", "both")

PASS: list[str] = []
FAIL: list[tuple[str, str]] = []


def check(label: str, condition: bool, detail: object = "") -> None:
    if condition:
        PASS.append(label)
    else:
        FAIL.append((label, str(detail)[:400]))


# --------------------------------------------------------------------------------------------------
# The stub `xcrun`, and the fixtures it reads.
#
# A fake bundle is a directory holding `summary.json`, `tests.json` and `xccov.json`. Omitting one is how the
# harness produces a bundle that cannot be read, which the collector must treat as missing evidence rather
# than as an empty suite.
# --------------------------------------------------------------------------------------------------

XCRUN_STUB = '''#!/usr/bin/env python3
import json, sys
from pathlib import Path

args = sys.argv[1:]
if not args:
    sys.exit(2)

tool = args[0]
path = None
for index, arg in enumerate(args):
    if arg == "--path" and index + 1 < len(args):
        path = Path(args[index + 1])
if tool == "xccov":
    # xccov takes the bundle as a trailing positional rather than behind --path.
    path = Path(args[-1])

if path is None or not path.is_dir():
    sys.exit(1)

if tool == "xcresulttool":
    wanted = "summary" if "summary" in args else "tests"
    fixture = path / f"{wanted}.json"
elif tool == "xccov":
    fixture = path / "xccov.json"
else:
    sys.exit(2)

if not fixture.is_file():
    sys.exit(1)
sys.stdout.write(fixture.read_text())
'''


def write_bundle(root: Path, name: str, *, summary: dict | None, tests: dict | None,
                 xccov: dict | None) -> Path:
    bundle = root / name
    bundle.mkdir(parents=True, exist_ok=True)
    for filename, payload in (("summary.json", summary), ("tests.json", tests), ("xccov.json", xccov)):
        if payload is not None:
            (bundle / filename).write_text(json.dumps(payload), encoding="utf-8")
    return bundle


def case(name: str, result: str, messages: list[str] | None = None) -> dict:
    node: dict = {"nodeType": "Test Case", "name": name, "result": result}
    if messages:
        node["children"] = [{"nodeType": "Failure Message", "name": m} for m in messages]
    return node


def tests_tree(bundle_name: str, suites: dict[str, list[dict]]) -> dict:
    return {
        "testNodes": [
            {
                "nodeType": "Test Plan",
                "name": "PayabliSDK-Package",
                "children": [
                    {
                        "nodeType": "Unit test bundle",
                        "name": bundle_name,
                        "children": [
                            {"nodeType": "Test Suite", "name": suite, "children": cases}
                            for suite, cases in suites.items()
                        ],
                    }
                ],
            }
        ]
    }


def summary_json(total: int, passed: int, failed: int, skipped: int) -> dict:
    return {
        "result": "Failed" if failed else "Passed",
        "totalTestCount": total,
        "passedTests": passed,
        "failedTests": failed,
        "skippedTests": skipped,
        "expectedFailures": 0,
        "testFailures": [],
    }


def xccov_json(targets: list[tuple[str, int, int]]) -> dict:
    return {
        "targets": [
            {
                "name": name,
                "executableLines": executable,
                "coveredLines": covered,
                "lineCoverage": (covered / executable) if executable else 0,
            }
            for name, executable, covered in targets
        ]
    }


# --------------------------------------------------------------------------------------------------
# The synthetic repository.
# --------------------------------------------------------------------------------------------------

def git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True, timeout=30, check=True)
    return result.stdout.strip()


def build_repo(root: Path) -> Path:
    """A repository with the collector, a few Swift files, and a history to attribute against."""
    repo = root / "repo"
    (repo / ".github" / "scripts").mkdir(parents=True)
    shutil.copy(COLLECTOR, repo / ".github" / "scripts" / "nightly_report.py")

    (repo / "Sources" / "PayabliSDKCore" / "Public").mkdir(parents=True)
    (repo / "Tests" / "PayabliSDKCoreTests").mkdir(parents=True)
    (repo / "Example" / "PayabliDemo" / "FlowTests").mkdir(parents=True)

    (repo / "Sources" / "PayabliSDKCore" / "Public" / "Widget.swift").write_text("// widget\n")
    (repo / "Tests" / "PayabliSDKCoreTests" / "WidgetTests.swift").write_text("// widget tests\n")
    # The same type name in two places, so the lookup has to refuse rather than pick one.
    (repo / "Tests" / "PayabliSDKCoreTests" / "AmbiguousTests.swift").write_text("// a\n")
    (repo / "Example" / "PayabliDemo" / "FlowTests" / "AmbiguousTests.swift").write_text("// b\n")

    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "harness@example.invalid")
    git(repo, "config", "user.name", "Harness Author")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "the commit that touched everything")
    return repo


def run_collector(repo: Path, bin_dir: Path, env_extra: dict[str, str], facts_name: str = "facts.json",
                  args: list[str] | None = None) -> tuple[int, str, dict | None, str, str]:
    """Run the collector as a subprocess. Returns (exit, stderr, facts, github_output, step_summary)."""
    facts_path = repo / facts_name
    output_path = repo / "github_output.txt"
    summary_path = repo / "step_summary.md"
    for path in (facts_path, output_path, summary_path):
        if path.exists():
            path.unlink()

    env = {
        "PATH": f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}",
        "HOME": str(repo),
        "GITHUB_OUTPUT": str(output_path),
        "GITHUB_STEP_SUMMARY": str(summary_path),
        "PLATFORM": "iOS",
        "GITHUB_REPOSITORY": "payabli/sdk-ios",
        **env_extra,
    }
    argv = [sys.executable, str(repo / ".github" / "scripts" / "nightly_report.py")]
    argv += args if args is not None else [str(facts_path)]
    result = subprocess.run(argv, cwd=repo, capture_output=True, text=True, timeout=120, check=False, env=env)
    facts = None
    if facts_path.is_file():
        try:
            facts = json.loads(facts_path.read_text())
        except json.JSONDecodeError:
            facts = None
    return (
        result.returncode,
        result.stderr,
        facts,
        output_path.read_text() if output_path.is_file() else "",
        summary_path.read_text() if summary_path.is_file() else "",
    )


ALL_GREEN_STEPS = {
    "SDK_OUTCOME": "success",
    "FLOW_OUTCOME": "success",
    "APP_BUILD_OUTCOME": "success",
    "DEVICE_COMPILE_OUTCOME": "success",
    "LIVE_BUNDLES_OUTCOME": "success",
    "XCFRAMEWORK_OUTCOME": "success",
}


def test_collector() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        stub = bin_dir / "xcrun"
        stub.write_text(XCRUN_STUB)
        stub.chmod(0o755)

        repo = build_repo(root)

        healthy_cov = xccov_json([
            ("PayabliSDKCore", 100, 80),
            ("PayabliSDKPayInPaymentFlow", 0, 0),
            ("PayabliSDKTapToPay", 50, 25),
            # PayabliSDKTelemetry deliberately absent, so the missing state is exercised.
        ])

        sdk_green = write_bundle(
            repo, "SDKTests.xcresult",
            summary=summary_json(3, 3, 0, 0),
            tests=tests_tree("PayabliSDKCoreTests", {"WidgetTests": [case("testOne()", "Passed")]}),
            xccov=healthy_cov,
        )
        flow_green = write_bundle(
            repo, "DemoFlowTests.xcresult",
            summary=summary_json(2, 2, 0, 0),
            tests=tests_tree("PayabliDemoFlowTests", {"StepTests": [case("testStep()", "Passed")]}),
            xccov=xccov_json([]),
        )
        base = {"SDK_RESULTS": str(sdk_green), "FLOW_RESULTS": str(flow_green)}

        # C1 --------------------------------------------------------------------------------------
        code, err, facts, output, _ = run_collector(repo, bin_dir, {**ALL_GREEN_STEPS, **base})
        check("C1 a clean run is green", code == 0 and facts and facts["verdict"] == "green", (code, err))
        check("C1b the verdict reaches GITHUB_OUTPUT", "verdict=green" in output, output)
        check("C1c the schema is the one the poster accepts", facts and facts["schema"] == 4, facts)

        # C2 --------------------------------------------------------------------------------------
        sdk_failed = write_bundle(
            repo, "Failed.xcresult",
            summary=summary_json(5, 3, 1, 1),
            tests=tests_tree("PayabliSDKCoreTests", {
                "WidgetTests": [
                    case("testOne()", "Passed"),
                    case("testTwo()", "Failed", ["WidgetTests.swift:5: XCTAssertEqual failed: nope",
                                                 "a second recorded failure"]),
                    case("testThree()", "Skipped", ["Test skipped - needs hardware"]),
                ],
            }),
            xccov=healthy_cov,
        )
        code, err, facts, output, summary = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "SDK_RESULTS": str(sdk_failed)}
        )
        check("C2 a failed test is red", facts and facts["verdict"] == "red", facts)
        check("C2b the verdict reaches GITHUB_OUTPUT as red", "verdict=red" in output, output)
        check("C3 a skipped test is not reported as a failure",
              facts and len(facts["failures"]) == 1, facts and facts["failures"])
        check("C3b the failure names its class and case",
              at((facts or {}).get("failures") or [], 0).get("label") == "WidgetTests > testTwo()", facts)
        check("C4 passed is derived rather than read, and the skip is named",
              at((facts or {}).get("suites") or [], 0).get("label") == "1 failed, 3 passed, 1 skipped / 5 tests",
              at((facts or {}).get("suites") or [], 0))
        check("C5 the trace is absent from the facts",
              "trace" not in at((facts or {}).get("failures") or [], 0),
              at((facts or {}).get("failures") or [], 0))
        check("C6 every recorded message reaches the job summary",
              "a second recorded failure" in summary, summary[:400])

        # C7 --------------------------------------------------------------------------------------
        silent = write_bundle(repo, "Silent.xcresult", summary=summary_json(0, 0, 0, 0),
                              tests=tests_tree("PayabliSDKCoreTests", {}), xccov=healthy_cov)
        _, _, facts, _, _ = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "SDK_RESULTS": str(silent)}
        )
        check("C7 a suite that ran and wrote no tests is red", facts and facts["verdict"] == "red", facts)
        check("C7b and says so rather than claiming a pass",
              at((facts or {}).get("suites") or [], 0).get("label") == "no results written",
              at((facts or {}).get("suites") or [], 0))

        # C8 --------------------------------------------------------------------------------------
        unreadable = write_bundle(repo, "Unreadable.xcresult", summary=None, tests=None, xccov=None)
        _, _, facts, _, _ = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "SDK_RESULTS": str(unreadable)}
        )
        check("C8 a bundle that cannot be read is red", facts and facts["verdict"] == "red", facts)

        # C9 --------------------------------------------------------------------------------------
        _, _, facts, _, _ = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "SDK_OUTCOME": "failure"}
        )
        check("C9 a failed step is red", facts and facts["verdict"] == "red", facts)
        _, _, facts, _, _ = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "SDK_OUTCOME": "skipped"}
        )
        check("C10 a skipped step is red, since none of them skips on purpose",
              facts and facts["verdict"] == "red", facts)
        _, _, facts, _, _ = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "SDK_OUTCOME": "unknown"}
        )
        check("C10b an unknown step outcome is red", facts and facts["verdict"] == "red", facts)

        # C11 -------------------------------------------------------------------------------------
        _, _, facts, _, _ = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "XCFRAMEWORK_OUTCOME": "failure"}
        )
        check("C11 a failed build is red", facts and facts["verdict"] == "red", facts)
        check("C11b and the build line names which one failed",
              at((facts or {}).get("suites") or [], 2).get("label") == "XCFramework failed, 3 built",
              at((facts or {}).get("suites") or [], 2))
        _, _, facts, _, _ = run_collector(repo, bin_dir, {**ALL_GREEN_STEPS, **base})
        check("C11c a clean build line says so without counting",
              at((facts or {}).get("suites") or [], 2).get("label") == "all built",
              at((facts or {}).get("suites") or [], 2))

        # C12 -------------------------------------------------------------------------------------
        attributed = write_bundle(
            repo, "Attributed.xcresult",
            summary=summary_json(1, 0, 1, 0),
            tests=tests_tree("PayabliSDKCoreTests", {
                "WidgetTests": [case("testTwo()", "Failed", ["boom"])],
            }),
            xccov=healthy_cov,
        )
        _, _, facts, _, _ = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "SDK_RESULTS": str(attributed)}
        )
        culprits = at((facts or {}).get("failures") or [], 0).get("culprits") or []
        whats = sorted(c["what"] for c in culprits)
        check("C12 the failing test and the type it names are both attributed",
              whats == ["Widget", "test"], culprits)
        check("C12b the author travels with the commit",
              all(c.get("author") == "Harness Author" for c in culprits), culprits)

        ambiguous = write_bundle(
            repo, "Ambiguous.xcresult",
            summary=summary_json(1, 0, 1, 0),
            tests=tests_tree("PayabliSDKCoreTests", {
                "AmbiguousTests": [case("testTwo()", "Failed", ["boom"])],
            }),
            xccov=healthy_cov,
        )
        _, _, facts, _, _ = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "SDK_RESULTS": str(ambiguous)}
        )
        check("C13 a type name that resolves to two files is attributed to neither",
              at((facts or {}).get("failures") or [], 0).get("culprits") == [],
              at((facts or {}).get("failures") or [], 0))

        # C14 -------------------------------------------------------------------------------------
        _, _, facts, _, _ = run_collector(repo, bin_dir, {**ALL_GREEN_STEPS, **base})
        rows = {m["module"]: m["state"]
                for m in (at((facts or {}).get("coverage") or [], 0).get("modules") or [])}
        check("C14 a measured module carries a percentage", rows.get("PayabliSDKCore") == "measured", rows)
        check("C14b a module with no executable lines is empty, not zero per cent",
              rows.get("PayabliSDKPayInPaymentFlow") == "empty", rows)
        check("C14c a module absent from the report is missing, not empty",
              rows.get("PayabliSDKTelemetry") == "missing", rows)
        check("C14d every module is named on every night",
              len(rows) == 4, rows)

        # C15 -------------------------------------------------------------------------------------
        escaping = write_bundle(
            repo, "Escaping.xcresult",
            summary=summary_json(1, 0, 1, 0),
            tests=tests_tree("PayabliSDKCoreTests", {
                "WidgetTests": [case("testTwo()", "Failed", ["</pre><script>alert(1)</script>"])],
            }),
            xccov=healthy_cov,
        )
        _, _, _, _, summary = run_collector(
            repo, bin_dir, {**ALL_GREEN_STEPS, **base, "SDK_RESULTS": str(escaping)}
        )
        check("C15 failure text cannot close the summary's own element",
              "</pre><script>" not in summary and "&lt;/pre&gt;" in summary, summary[:300])

        # C16 -------------------------------------------------------------------------------------
        code, _, _, _, _ = run_collector(repo, bin_dir, {**ALL_GREEN_STEPS, **base}, args=[])
        check("C16 the wrong argument count exits 2", code == 2, code)

        # C17 -------------------------------------------------------------------------------------
        # A run with no results at all, which is what a job that died before the tests looks like.
        _, _, facts, _, _ = run_collector(
            repo, bin_dir,
            {**ALL_GREEN_STEPS, "SDK_RESULTS": str(repo / "nope.xcresult"),
             "FLOW_RESULTS": str(repo / "nope.xcresult")},
        )
        check("C17 no bundles at all is red", facts and facts["verdict"] == "red", facts)


# --------------------------------------------------------------------------------------------------
# The fake Slack, and the poster half.
# --------------------------------------------------------------------------------------------------

class FakeHandler(BaseHTTPRequestHandler):
    def log_message(self, *args) -> None:  # noqa: D102 - silence the default stderr logging
        pass

    def _reply(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler's naming
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8") if length else "{}"
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {}
        method = self.path.rsplit("/", 1)[-1]
        server = self.server
        server.calls.append((method, payload, dict(self.headers)))
        self._reply(server.responses.get(method, {"ok": True, "ts": "111.222"}))

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        # The compare endpoint carries both shas in the path, so it is keyed by name rather than by its
        # last segment the way the others are.
        method = "compare" if "/compare/" in path else path.rsplit("/", 1)[-1]
        server = self.server
        server.calls.append((method, {"query": self.path}, dict(self.headers)))
        if method in server.responses:
            self._reply(server.responses[method])
            return
        self._reply({"ok": True})


class FakeSlack(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self) -> None:
        super().__init__(("127.0.0.1", 0), FakeHandler)
        self.calls: list[tuple[str, dict, dict]] = []
        self.responses: dict[str, dict] = {}

    @property
    def base(self) -> str:
        return f"http://127.0.0.1:{self.server_address[1]}"


def facts_fixture(verdict: str = "green", failures: list[dict] | None = None,
                  platform: str = "iOS") -> dict:
    return {
        "schema": 4,
        "verdict": verdict,
        "platform": platform,
        "suites": [
            {"name": "SDK", "label": "all 3 passed"},
            {"name": "Sample app", "label": "all 2 passed"},
            {"name": "Builds", "label": "all built"},
        ],
        "coverage": [{
            "label": "line",
            "modules": [
                {"module": "PayabliSDKCore", "percent": 80.0, "state": "measured"},
                {"module": "PayabliSDKTapToPay", "percent": None, "state": "empty"},
                {"module": "PayabliSDKTelemetry", "percent": None, "state": "missing"},
            ],
        }],
        "failures": failures or [],
    }


def failure_fixture(label: str = "WidgetTests > testTwo()", detail: str = "boom",
                    culprits: list[dict] | None = None) -> dict:
    return {
        "suite": label.split(" > ")[0],
        "case": label.split(" > ")[-1],
        "label": label,
        "detail": detail,
        "kind": "failure",
        "culprits": culprits if culprits is not None else [
            {"sha": "abc1234", "author": "Someone", "email": "s@example.invalid",
             "subject": "a change", "what": "test"},
        ],
    }


def run_poster(poster, server: FakeSlack, facts: dict | None, env_extra: dict[str, str],
               tmp: Path) -> int:
    facts_path = tmp / "facts.json"
    if facts is None:
        if facts_path.exists():
            facts_path.unlink()
    else:
        facts_path.write_text(json.dumps(facts), encoding="utf-8")

    saved = dict(os.environ)
    os.environ.update({
        "SLACK_BOT_TOKEN": "xoxb-harness",
        "SLACK_CHANNEL_ID": "C123",
        "GITHUB_SERVER_URL": "https://github.test",
        "GITHUB_REPOSITORY": "payabli/sdk-ios",
        "GITHUB_RUN_ID": "999",
        "GITHUB_SHA": "0123456789abcdef",
        "GITHUB_REF_NAME": "main",
        "GITHUB_API_URL": server.base,
        "PLATFORM": "iOS",
        **env_extra,
    })
    server.calls.clear()
    try:
        return _call_main(poster, facts_path)
    finally:
        os.environ.clear()
        os.environ.update(saved)


def _call_main(poster, facts_path: Path) -> int:
    argv = sys.argv
    sys.argv = ["nightly_slack.py", str(facts_path)]
    try:
        return poster.main()
    finally:
        sys.argv = argv


def posted(server: FakeSlack, method: str) -> list[dict]:
    return [payload for name, payload, _ in server.calls if name == method]


# Reading a message the poster did not send must fail a check, never raise. A harness that dies part way
# prints no FAIL line and no summary, which on a terminal reads exactly like one that passed, and every
# check after the exception silently does not run.
def at(items: list, index: int) -> dict:
    return items[index] if -len(items) <= index < len(items) else {}


def block_text(message: dict, index: int = 0) -> str:
    block = at(message.get("blocks") or [], index)
    return (block.get("text") or {}).get("text") or ""


def headline(server: FakeSlack) -> str:
    return block_text(at(posted(server, "chat.postMessage"), 0))


def position(order: list[str], name: str) -> int:
    """Where a call appears, or -1 when it never happened. `list.index` raises, which is not a failure."""
    return order.index(name) if name in order else -1


def test_poster() -> None:
    sys.path.insert(0, str(SCRIPTS))
    import nightly_slack as poster  # noqa: PLC0415 - deliberately imported after the path is set

    server = FakeSlack()
    threading.Thread(target=server.serve_forever, daemon=True).start()
    poster.SLACK_API = server.base

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)

        # P1 --------------------------------------------------------------------------------------
        server.responses = {
            "chat.scheduleMessage": {"ok": True, "scheduled_message_id": "Q1"},
            "chat.scheduledMessages.list": {"ok": True, "scheduled_messages": []},
        }
        code = run_poster(poster, server, facts_fixture("green"), {"LIVENESS_OWNER": "true"}, root)
        check("P1 a green scheduled run posts nothing", not posted(server, "chat.postMessage"),
              server.calls)
        check("P1b and arms the liveness alarm", len(posted(server, "chat.scheduleMessage")) == 1,
              server.calls)
        check("P1c and exits zero", code == 0, code)
        armed = at(posted(server, "chat.scheduleMessage"), 0)
        check("P1d the alarm carries the platform-scoped marker",
              "nightly-liveness:iOS" in armed.get("text", ""), armed.get("text"))
        check("P1e the marker is not the Android one, and neither contains the other",
              "nightly-liveness:Android" not in armed.get("text", "")
              and "nightly-liveness:iOS" not in "nightly-liveness:Android"
              and "nightly-liveness:Android" not in "nightly-liveness:iOS",
              armed.get("text"))
        check("P1f the alarm is not scheduled with metadata, which would stop it posting",
              "metadata" not in armed, sorted(armed))

        # P2 --------------------------------------------------------------------------------------
        code = run_poster(poster, server, facts_fixture("green"), {"LIVENESS_OWNER": "false"}, root)
        check("P2 a green dispatch posts nothing", not posted(server, "chat.postMessage"), server.calls)
        check("P2b and does not vouch for the schedule",
              not posted(server, "chat.scheduleMessage"), server.calls)

        # P3 --------------------------------------------------------------------------------------
        server.responses = {"chat.scheduleMessage": {"ok": False, "error": "invalid_channel"}}
        run_poster(poster, server, facts_fixture("green"), {"LIVENESS_OWNER": "true"}, root)
        check("P3 a green run whose alarm could not be armed posts the summary anyway",
              len(posted(server, "chat.postMessage")) == 1, server.calls)

        # P4 --------------------------------------------------------------------------------------
        server.responses = {
            "chat.postMessage": {"ok": True, "ts": "111.222"},
            "chat.scheduleMessage": {"ok": True, "scheduled_message_id": "Q2"},
            "chat.scheduledMessages.list": {"ok": True, "scheduled_messages": []},
        }
        run_poster(poster, server, facts_fixture("red", [failure_fixture()]),
                   {"LIVENESS_OWNER": "true"}, root)
        messages = posted(server, "chat.postMessage")
        check("P4 a red run posts a summary and a threaded reply", len(messages) == 2, server.calls)
        check("P4b the reply is threaded to the summary",
              at(messages, 1).get("thread_ts") == "111.222", at(messages, 1))
        check("P4c the summary headline names the platform and the verdict",
              "iOS · Nightly failed" in block_text(at(messages, 0)), at(messages, 0))
        check("P4d the thread labels the attribution a heuristic",
              "heuristic" in block_text(at(messages, 1)), at(messages, 1))

        # P5 --------------------------------------------------------------------------------------
        run_poster(
            poster, server,
            facts_fixture("red", [failure_fixture(label="<!channel> > testTwo()", detail="<!here> boom")]),
            {"LIVENESS_OWNER": "true"}, root,
        )
        rendered = json.dumps(posted(server, "chat.postMessage"))
        check("P5 a Slack control sequence in a test name cannot reach the channel",
              "<!channel>" not in rendered and "&lt;!channel&gt;" in rendered, rendered[:400])
        check("P5b nor in a failure message", "<!here>" not in rendered, rendered[:400])

        # P5c -------------------------------------------------------------------------------------
        # The failure message is never rendered, whatever it says. XCTest quotes both operands of a
        # mismatch, and the suites here assert over card numbers, CVVs, expiries, cardholder names and
        # ACH account numbers, so a rendered message would copy those into Slack storage.
        leaky = failure_fixture(
            detail='XCTAssertEqual failed: ("4111111111111111") is not equal to ("4242424242424242")',
        )
        run_poster(poster, server, facts_fixture("red", [leaky]), {"LIVENESS_OWNER": "true"}, root)
        rendered = json.dumps(posted(server, "chat.postMessage"))
        check("P5c a failed payment assertion cannot copy its operands into Slack",
              "4111111111111111" not in rendered and "XCTAssertEqual" not in rendered, rendered[:400])
        # The label is escaped on the way in, so `>` reaches the block as `&gt;`. Asserting the raw form
        # would fail against correct output, which is the shape of check that gets "fixed" by weakening it.
        check("P5d the test that failed is still named, with a link to the message",
              "WidgetTests &gt; testTwo()" in rendered and "failure message" in rendered, rendered[:400])

        # P6 --------------------------------------------------------------------------------------
        tampered = facts_fixture("red", [failure_fixture()])
        tampered["run"] = {"url": "https://evil.test|x><!channel>"}
        run_poster(poster, server, tampered, {"LIVENESS_OWNER": "true"}, root)
        rendered = json.dumps(posted(server, "chat.postMessage"))
        check("P6 the run link is rebuilt from the environment, never read from the facts",
              "evil.test" not in rendered and "https://github.test/payabli/sdk-ios/actions/runs/999" in rendered,
              rendered[:400])

        # P7 --------------------------------------------------------------------------------------
        run_poster(poster, server, facts_fixture("green"),
                   {"LIVENESS_OWNER": "true", "NIGHTLY_JOB_RESULT": "failure"}, root)
        text = headline(server)
        check("P7 collected green over a failed job reports red", "Nightly failed" in text, text[:200])
        check("P7b and says which to believe", "Believe the run" in text, text[:400])

        # P8 --------------------------------------------------------------------------------------
        run_poster(poster, server, None, {"NIGHTLY_JOB_RESULT": "success"}, root)
        text = headline(server)
        check("P8 a lost report over a passing job is a warning, not an alarm",
              ":warning:" in text and "Nightly · no report" in text, text[:200])

        run_poster(poster, server, None, {"NIGHTLY_JOB_RESULT": "failure"}, root)
        text = headline(server)
        check("P9 a dead test job is an alarm", ":red_circle:" in text, text[:200])

        # P10 -------------------------------------------------------------------------------------
        stale = facts_fixture("red", [failure_fixture()])
        stale["schema"] = 3
        run_poster(poster, server, stale, {"NIGHTLY_JOB_RESULT": "failure"}, root)
        text = headline(server)
        check("P10 an unrecognised schema falls back rather than half-rendering",
              "Nightly · no report" in text, text[:200])

        (root / "facts.json").write_text("[]", encoding="utf-8")
        code = _call_main(poster, root / "facts.json")
        check("P11 a facts file that is not an object never raises", code == 0, code)

        # P12 -------------------------------------------------------------------------------------
        server.responses = {
            "chat.postMessage": {"ok": True, "ts": "111.222"},
            "chat.scheduleMessage": {"ok": True, "scheduled_message_id": "NEW"},
            "chat.scheduledMessages.list": {
                "ok": True,
                "scheduled_messages": [
                    {"id": "OLD", "post_at": 1, "text": "[nightly-liveness:iOS] old"},
                    {"id": "NEWER", "post_at": 10 ** 12, "text": "[nightly-liveness:iOS] newer"},
                    {"id": "ANDROID", "post_at": 1, "text": "[nightly-liveness:Android] theirs"},
                    {"id": "OTHER", "post_at": 1, "text": "someone else's message"},
                ],
            },
        }
        run_poster(poster, server, facts_fixture("green"), {"LIVENESS_OWNER": "true"}, root)
        order = [name for name, _, _ in server.calls]
        deleted = {p.get("scheduled_message_id") for p in posted(server, "chat.deleteScheduledMessage")}
        armed_at = position(order, "chat.scheduleMessage")
        swept_at = position(order, "chat.scheduledMessages.list")
        check("P12 the new alarm is armed before the old one is cancelled",
              armed_at >= 0 and swept_at >= 0 and armed_at < swept_at, order)
        check("P13 only a strictly older alarm of this platform is cancelled",
              deleted == {"OLD"}, deleted)

        # P14 -------------------------------------------------------------------------------------
        server.responses = {
            "chat.postMessage": {"ok": True, "ts": "111.222"},
            "chat.scheduleMessage": {"ok": True, "scheduled_message_id": "Q9"},
            "chat.scheduledMessages.list": {"ok": True, "scheduled_messages": []},
            # The last-green lookup: this run, then the workflow's runs, then the compare.
            "999": {"workflow_id": 77},
            "runs": {"workflow_runs": [{"id": 1, "head_sha": "f" * 40}]},
        }
        old = {"sha": "abc1234", "author": "Someone", "email": "s@example.invalid",
               "subject": "old work", "what": "test"}
        since = {"base": "fffffff", "head": "0123456", "url": "https://github.test/c",
                 "count": 2, "shas": ["9" * 40, "8" * 40]}
        blocks = poster.thread_blocks(facts_fixture("red", [failure_fixture(culprits=[old])]), since)
        text = blocks[0]["text"]["text"]
        check("P14 a commit that predates the last green run is not named as a culprit",
              "unchanged since the last green nightly" in text and "Someone" not in text, text[:400])

        inside = {**old, "sha": "9999999"}
        blocks = poster.thread_blocks(facts_fixture("red", [failure_fixture(culprits=[inside])]), since)
        text = blocks[0]["text"]["text"]
        check("P14b a commit inside the range is named", "last touched by" in text, text[:400])

        blocks = poster.thread_blocks(facts_fixture("red", [failure_fixture(culprits=[old])]), None)
        text = blocks[0]["text"]["text"]
        check("P14c an unknown range names the commit rather than clearing it",
              "last touched by" in text, text[:400])

        check("P14d an empty range is not the same as an unknown one",
              poster.landed_before_last_green(old, {"shas": []}) is True
              and poster.landed_before_last_green(old, {"shas": None}) is False,
              "")

        # P19 -------------------------------------------------------------------------------------
        # The last-green lookup, driven through the fake Actions API rather than hand-built. Every branch
        # below decides whether a commit is named as a culprit, and each was previously reachable only in
        # production: nothing set GITHUB_TOKEN, so the function returned at its first guard and the fake's
        # responses were never consumed.
        head = "0123456789abcdef"

        def lookup(responses: dict, token: str = "gh-harness") -> dict | None:
            server.responses = {"999": {"workflow_id": 77}, **responses}
            saved = dict(os.environ)
            os.environ.update({
                "GITHUB_TOKEN": token,
                "GITHUB_REPOSITORY": "payabli/sdk-ios",
                "GITHUB_RUN_ID": "999",
                "GITHUB_SHA": head,
                "GITHUB_REF_NAME": "main",
                "GITHUB_SERVER_URL": "https://github.test",
                "GITHUB_API_URL": server.base,
            })
            if not token:
                os.environ.pop("GITHUB_TOKEN", None)
            server.calls.clear()
            try:
                return poster.commits_since_last_green()
            finally:
                os.environ.clear()
                os.environ.update(saved)

        got = lookup({"runs": {"workflow_runs": [{"id": 1, "head_sha": head}]}})
        check("P19 a re-run of the commit that went green is an empty range, not an unknown one",
              got is not None and got.get("empty") is True and got.get("shas") == [], got)

        got = lookup({
            "runs": {"workflow_runs": [{"id": 1, "head_sha": "f" * 40}]},
            "compare": {"status": "ahead", "total_commits": 2,
                        "commits": [{"sha": "9" * 40}, {"sha": "8" * 40}]},
        })
        check("P20 an ahead range carries its count and every sha in it",
              got is not None and got.get("count") == 2 and len(got.get("shas") or []) == 2, got)

        got = lookup({
            "runs": {"workflow_runs": [{"id": 1, "head_sha": "f" * 40}]},
            "compare": {"status": "behind", "total_commits": 0, "commits": []},
        })
        check("P21 a checkout behind the baseline is an empty range",
              got is not None and got.get("empty") is True, got)

        got = lookup({
            "runs": {"workflow_runs": [{"id": 1, "head_sha": "f" * 40}]},
            "compare": {"status": "diverged", "total_commits": 5, "commits": []},
        })
        check("P22 rewritten history is unknown rather than empty, so nobody is cleared", got is None, got)

        got = lookup({
            "runs": {"workflow_runs": [{"id": 1, "head_sha": "f" * 40}]},
            # total_commits counts the whole range while the array pages at 250, so a short list is a
            # truncated one and every absence from it means nothing.
            "compare": {"status": "ahead", "total_commits": 300, "commits": [{"sha": "9" * 40}]},
        })
        check("P23 a truncated compare yields no sha list rather than a partial one",
              got is not None and got.get("shas") is None, got)

        got = lookup({"runs": {"workflow_runs": []}})
        check("P24 no previous success on this branch is unknown rather than empty", got is None, got)

        got = lookup({"runs": {"workflow_runs": [{"id": 1, "head_sha": "f" * 40}]}}, token="")
        check("P25 without a token the range is unknown and nothing is looked up",
              got is None and not server.calls, (got, len(server.calls)))

        # P15 -------------------------------------------------------------------------------------
        # Long through the parts that are still rendered. The failure message is no longer one of them,
        # so padding `detail` would leave the trim loop with nothing to trim and the check would pass
        # without reaching the behaviour it names.
        many = [
            failure_fixture(
                label=f"Suite{i}WithAVeryLongNameThatFillsTheBlock > test{i}()",
                culprits=[{"sha": f"abc{i:04}", "author": "Someone", "email": "s@example.invalid",
                           "subject": "a commit subject long enough to fill the block " * 3,
                           "what": "test"}],
            )
            for i in range(20)
        ]
        blocks = poster.thread_blocks(facts_fixture("red", many), None)
        text = blocks[0]["text"]["text"]
        check("P15 an over-long failure list is trimmed to whole entries",
              len(text) <= poster.SLACK_BLOCK_LIMIT, len(text))
        check("P15b and always says how many are missing", "further failure(s) not listed" in text,
              text[-200:])

        # P16 -------------------------------------------------------------------------------------
        run_poster(poster, server, facts_fixture("red", []), {"LIVENESS_OWNER": "true"}, root)
        check("P16 a red run with no failures posts no thread",
              len(posted(server, "chat.postMessage")) == 1, server.calls)

        # P17 -------------------------------------------------------------------------------------
        saved = dict(os.environ)
        os.environ.pop("SLACK_BOT_TOKEN", None)
        os.environ.pop("SLACK_CHANNEL_ID", None)
        server.calls.clear()
        code = _call_main(poster, root / "facts.json")
        os.environ.clear()
        os.environ.update(saved)
        check("P17 no credentials posts nothing and still exits zero",
              code == 0 and not server.calls, (code, server.calls))

        # P18 -------------------------------------------------------------------------------------
        check("P18 the wrong argument count exits 2", _bad_args(poster) == 2, "")

    server.shutdown()


def _bad_args(poster) -> int:
    argv = sys.argv
    sys.argv = ["nightly_slack.py"]
    try:
        return poster.main()
    finally:
        sys.argv = argv


# --------------------------------------------------------------------------------------------------
# The workflows themselves.
# --------------------------------------------------------------------------------------------------

def test_workflows() -> None:
    import yaml  # noqa: PLC0415 - only this half needs it, and the job asserts it is present

    nightly = yaml.safe_load(NIGHTLY_WORKFLOW.read_text())
    scripts = yaml.safe_load(SCRIPTS_WORKFLOW.read_text())
    nightly_text = NIGHTLY_WORKFLOW.read_text()

    # PyYAML resolves the bare key `on` to the boolean True, which is the one YAML 1.1 quirk this file hits.
    triggers = nightly.get("on", nightly.get(True)) or {}
    check("W1 the nightly never runs on a push or a pull request",
          "push" not in triggers and "pull_request" not in triggers, sorted(triggers))
    check("W2 the nightly runs on a schedule and by hand",
          "schedule" in triggers and "workflow_dispatch" in triggers, sorted(triggers))

    jobs = nightly.get("jobs") or {}
    holders = [
        name for name, job in jobs.items()
        if "SLACK_BOT_TOKEN" in yaml.safe_dump(job)
    ]
    check("W3 exactly one job names the Slack token", holders == ["report"], holders)
    check("W3b and it is not the job that runs the tests", "nightly" not in holders, holders)

    report = jobs.get("report") or {}
    check("W4 the report job cannot redden a green run",
          report.get("continue-on-error") is True, report.get("continue-on-error"))
    check("W4b and runs even when the test job did not finish",
          "cancelled()" in str(report.get("if", "")), report.get("if"))
    check("W4c and waits for the test job", report.get("needs") == "nightly", report.get("needs"))

    owner = ""
    for step in report.get("steps") or []:
        owner = ((step.get("env") or {}).get("LIVENESS_OWNER") or owner)
    operands = [part.strip() for part in owner.split("&&")]
    check("W5 the liveness owner requires both conditions rather than either",
          "||" not in owner and len(operands) == 2, owner)
    check("W5b one of them is that this run came from the schedule",
          any("event_name == 'schedule'" in part for part in operands), owner)
    check("W5c the other compares the ref to the default branch, and not by inequality",
          any("ref_name" in part and "default_branch" in part for part in operands)
          and "!=" not in owner, owner)

    test_job = jobs.get("nightly") or {}
    steps = test_job.get("steps") or []
    suites = [s for s in steps if s.get("id") in
              {"sdk", "flow", "app", "device_compile", "bundles", "xcframework"}]
    check("W6 every suite and build carries an id and continues on error",
          len(suites) == 6 and all(s.get("continue-on-error") is True for s in suites),
          [(s.get("id"), s.get("continue-on-error")) for s in suites])
    check("W6b and each one is bounded",
          all(isinstance(s.get("timeout-minutes"), int) for s in suites),
          [(s.get("id"), s.get("timeout-minutes")) for s in suites])

    job_bound = test_job.get("timeout-minutes")
    step_bounds = sum(s.get("timeout-minutes", 0) for s in steps if isinstance(s.get("timeout-minutes"), int))
    check("W7 the job bound is a backstop above the sum of its steps",
          isinstance(job_bound, int) and job_bound > step_bounds, (job_bound, step_bounds))

    gate = next((s for s in steps if "verdict" in str(s.get("run", ""))), None)
    check("W8 the gate reads the collector's verdict", gate is not None, "")
    if gate is not None:
        missing = [s.get("id") for s in suites if f"steps.{s['id']}.outcome" not in gate.get("run", "")]
        check("W8b and every suite and build outcome", not missing, missing)
        check("W8c and runs even after a failure", gate.get("if") == "always()", gate.get("if"))

    collect = next((s for s in steps if s.get("id") == "collect"), None)
    check("W9 the collector runs in the job that holds the results and the history",
          collect is not None and "nightly_report.py" in collect.get("run", ""), collect)

    check("W10 the checkout is deep, so the attribution has a history to read",
          any((s.get("with") or {}).get("fetch-depth") == 0 for s in steps), "")

    scripts_triggers = scripts.get("on", scripts.get(True)) or {}
    guarded = {".github/scripts/**", ".github/workflows/scripts.yml", ".github/workflows/nightly.yml"}
    # Per event, not across both. A file listed only under `push` leaves the guard not running on the
    # pull request that changes it, which is the whole case it exists for, and a union would call that
    # covered.
    for event in ("pull_request", "push"):
        watched = set((scripts_triggers.get(event) or {}).get("paths") or [])
        check(f"W11 the harness runs on {event} for every file it makes claims about",
              guarded <= watched, sorted(watched))

    check("W12 the hardware-only exclusion is wired on both test steps",
          nightly_text.count("HARDWARE_ONLY_TESTS") >= 4, nightly_text.count("HARDWARE_ONLY_TESTS"))
    check("W13 the platform is named at workflow level, where the no-report path can read it",
          (nightly.get("env") or {}).get("PLATFORM") == "iOS", nightly.get("env"))

    # The liveness window and the job's own ceiling are one decision in two files. The alarm is armed when
    # a run reports and cancelled when the next one does, so a run that takes hours longer than the one
    # before it widens that gap; sized only from the 24-hour cadence, a slow-but-healthy night fires the
    # previous alarm. Tied here so raising the job bound without re-sizing the window fails rather than
    # producing a false alarm months later.
    sys.path.insert(0, str(SCRIPTS))
    import nightly_slack as poster_module  # noqa: PLC0415 - needs the path set above

    cadence_hours = 24
    delay_margin_hours = 1
    needed = cadence_hours + (job_bound or 0) / 60 + delay_margin_hours
    check("W14 the liveness window covers the cadence plus the longest healthy run",
          poster_module.SWITCH_HOURS >= needed,
          f"SWITCH_HOURS={poster_module.SWITCH_HOURS} needs >= {needed:.1f} "
          f"(24h cadence + {job_bound}min job bound + {delay_margin_hours}h delay)")


def main() -> int:
    if ONLY not in HALVES:
        print(f"NIGHTLY_ONLY={ONLY!r} is not one of {', '.join(HALVES)}")
        return 2

    started = time.time()
    if ONLY in ("collector", "both"):
        test_collector()
    if ONLY in ("poster", "both"):
        test_poster()
    if ONLY in ("workflows", "both"):
        test_workflows()

    for label in PASS:
        print(f"  ok   {label}")
    for label, detail in FAIL:
        print(f"  FAIL {label}\n         {detail}")

    # A harness that asserted nothing looks exactly like one that passed, so it is a failure here.
    if not PASS and not FAIL:
        print("  FAILED: no checks ran at all")
        return 1

    print(f"\n{len(PASS)} passed, {len(FAIL)} failed in {time.time() - started:.1f}s")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
