#!/usr/bin/env python3
"""Break each thing the nightly reporter claims, one at a time, and confirm a check goes red.

`verify.py` says the reporter behaves. This says the checks would notice if it stopped. Those are different
claims, and only the second one catches a check that passes vacuously: an assertion against a value nothing
produces, a condition that is true whatever the code does, or a fixture that never reaches the branch it was
written for.

Every mutation runs against copies in a scratch directory. Nothing in the working tree is read for anything
but its contents and nothing in it is written, so an interrupted run leaves nothing behind.

Three safeguards, and each has a job:

  * an anchor must match **exactly once**, so a mutation cannot silently apply somewhere else or nowhere
  * the mutated file must still parse, so a check going red proves the behaviour changed rather than that
    the file stopped loading
  * the unmutated copy must be fully green first, so a mutation cannot be credited with a failure that was
    already there

A mutation whose anchor no longer matches reports INVALID and fails the run. Re-point the anchor in the same
change that moved the code; deleting the row is how coverage disappears quietly.

    python3 .github/scripts/tests/sabotage.py
"""

from __future__ import annotations

import ast
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
COPIED = (
    ".github/scripts/nightly_report.py",
    ".github/scripts/nightly_slack.py",
    ".github/scripts/tests/verify.py",
    ".github/workflows/nightly.yml",
    ".github/workflows/scripts.yml",
)

REPORT = ".github/scripts/nightly_report.py"
SLACK = ".github/scripts/nightly_slack.py"
NIGHTLY = ".github/workflows/nightly.yml"
SCRIPTS_YML = ".github/workflows/scripts.yml"


class Mutation:
    def __init__(self, name: str, path: str, anchor: str, replacement: str, expect: str,
                 half: str) -> None:
        self.name = name
        self.path = path
        self.anchor = anchor
        self.replacement = replacement
        # The check label prefix that must appear among verify.py's failures.
        self.expect = expect
        # Which half of verify.py can see it, so a mutation does not pay for the other two.
        self.half = half


MUTATIONS = [
    # ---- the collector's verdict --------------------------------------------------------------
    Mutation(
        "a suite that wrote no results is accepted",
        REPORT, "        or sdk_missing\n", "", "C7", "collector",
    ),
    Mutation(
        "a skipped step is treated as benign",
        REPORT,
        'steps_bad = sdk_step != "success" or flow_step != "success"',
        'steps_bad = sdk_step not in ("success", "skipped") or flow_step != "success"',
        "C10", "collector",
    ),
    Mutation(
        "an unknown step outcome is treated as a pass",
        REPORT,
        'sdk_step = os.environ.get("SDK_OUTCOME", "unknown")',
        'sdk_step = os.environ.get("SDK_OUTCOME", "unknown").replace("unknown", "success")',
        "C10b", "collector",
    ),
    Mutation(
        "a failed build does not redden the run",
        REPORT, "        or builds_bad\n", "", "C11", "collector",
    ),
    Mutation(
        "the verdict is never published to the gate",
        REPORT,
        'handle.write(f"verdict={\'red\' if red else \'green\'}\\n")',
        "pass",
        "C1b", "collector",
    ),
    # ---- the collector's counting ---------------------------------------------------------------
    Mutation(
        "passed is read rather than derived, so a skip reads as a pass",
        REPORT, "passed = max(total - failed - skipped, 0)", "passed = max(total - failed, 0)",
        "C4", "collector",
    ),
    Mutation(
        "a skipped test is reported as a failure",
        REPORT,
        'if kind == "Test Case" and node.get("result") == "Failed":',
        'if kind == "Test Case" and node.get("result") in ("Failed", "Skipped"):',
        "C3", "collector",
    ),
    # ---- the collector's attribution ------------------------------------------------------------
    Mutation(
        "an ambiguous type name is attributed to the first file found",
        REPORT,
        "found = matches[0].relative_to(REPO_ROOT) if len(matches) == 1 else None",
        "found = matches[0].relative_to(REPO_ROOT) if matches else None",
        "C13", "collector",
    ),
    # ---- the collector's rendering --------------------------------------------------------------
    Mutation(
        "failure text reaches the job summary unescaped",
        REPORT, "<pre>{html.escape(trace)}</pre>", "<pre>{trace}</pre>", "C15", "collector",
    ),
    Mutation(
        "a module with no code is reported as one with no report",
        REPORT, 'out.append((name, None, "empty"))', 'out.append((name, None, "missing"))',
        "C14b", "collector",
    ),

    # ---- the poster's escaping and links --------------------------------------------------------
    Mutation(
        "test data reaches Slack unescaped",
        SLACK,
        'escaped = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")',
        "escaped = text",
        "P5", "poster",
    ),
    Mutation(
        "the run link is taken from somewhere the facts could reach",
        SLACK,
        '"url": f"{server}/{repo}/actions/runs/{run_id}" if repo and run_id',
        '"url": f"https://evil.test/{repo}/actions/runs/{run_id}" if repo and run_id',
        "P6", "poster",
    ),
    Mutation(
        "the failure message is rendered into the Slack thread again",
        SLACK,
        'entry = f"\\n• `{mrkdwn(failure[\'label\'])}` · <{run_url}|failure message>"',
        'entry = f"\\n• `{mrkdwn(failure[\'label\'])}` · <{run_url}|failure message>\\n  {mrkdwn(failure[\'detail\'])}"',
        "P5c", "poster",
    ),
    # ---- the poster's green path ----------------------------------------------------------------
    Mutation(
        "a green run posts into the channel anyway",
        SLACK, "if green and reset_liveness_switch(token, channel):", "if False:", "P1", "poster",
    ),
    Mutation(
        "a run that does not own the switch vouches for the schedule",
        SLACK, "if green and not owns_liveness_switch():", "if False:", "P2b", "poster",
    ),
    # ---- the poster's liveness switch ------------------------------------------------------------
    Mutation(
        "the stale alarm is cancelled before the new one is armed",
        SLACK,
        "    armed = arm_liveness_switch(token, channel, marker, subject)\n"
        "    if not armed:",
        "    cancel_stale_switches(token, channel, keep='', keep_post_at=0, marker=marker)\n"
        "    armed = arm_liveness_switch(token, channel, marker, subject)\n"
        "    if not armed:",
        "P12", "poster",
    ),
    Mutation(
        "the sweep cancels an alarm it cannot prove is older",
        SLACK,
        "if not isinstance(post_at, int) or post_at >= keep_post_at:",
        "if False:",
        "P13", "poster",
    ),
    Mutation(
        "the sweep cancels the other platform's alarm",
        SLACK,
        'if marker not in (message.get("text") or ""):',
        "if False:",
        "P13", "poster",
    ),
    # ---- the poster's reconciliation --------------------------------------------------------------
    Mutation(
        "the collected verdict is believed over the job result",
        SLACK, 'unfinished = job_result != "success"', "unfinished = False", "P7", "poster",
    ),
    Mutation(
        "an unrecognised facts schema is rendered anyway",
        SLACK, "if raw.get(\"schema\") != SUPPORTED_SCHEMA:", "if False:", "P10", "poster",
    ),
    Mutation(
        "a lost report and a dead job are reported the same way",
        SLACK, '    if job_result == "success":\n        icon = ":warning:"',
        '    if False:\n        icon = ":warning:"',
        "P8", "poster",
    ),
    # ---- the poster's trimming and culprits --------------------------------------------------------
    Mutation(
        "an over-long failure list is emitted whole",
        SLACK, "if len(text) <= SLACK_BLOCK_LIMIT or not entries:", "if True:", "P15b", "poster",
    ),
    Mutation(
        "a commit that predates the last green run is still blamed",
        SLACK, "if landed_before_last_green(commit, since_green):", "if False:", "P14", "poster",
    ),
    Mutation(
        "an unknown commit range is read as an empty one",
        SLACK, 'shas = (since_green or {}).get("shas")', 'shas = (since_green or {}).get("shas") or []',
        "P14c", "poster",
    ),

    # ---- the workflows -------------------------------------------------------------------------
    Mutation(
        "the nightly starts running on pull requests",
        NIGHTLY, "on:\n  workflow_dispatch:", "on:\n  pull_request:\n  workflow_dispatch:",
        "W1", "workflows",
    ),
    Mutation(
        "either condition is enough to own the liveness switch",
        NIGHTLY,
        "github.event_name == 'schedule' && github.ref_name == github.event.repository.default_branch",
        "github.event_name == 'schedule' || github.ref_name == github.event.repository.default_branch",
        "W5", "workflows",
    ),
    Mutation(
        "a failing build ends the job before the report is collected",
        NIGHTLY,
        "        id: xcframework\n        continue-on-error: true\n",
        "        id: xcframework\n",
        "W6", "workflows",
    ),
    Mutation(
        "the gate stops reading one of the outcomes",
        NIGHTLY,
        '"${{ steps.bundles.outcome }}" "${{ steps.xcframework.outcome }}"',
        '"${{ steps.xcframework.outcome }}"',
        "W8b", "workflows",
    ),
    Mutation(
        "the harness stops running on the workflow it makes claims about",
        SCRIPTS_YML,
        "      - '.github/workflows/nightly.yml'\n  push:",
        "  push:",
        "W11", "workflows",
    ),
    Mutation(
        "the checkout goes shallow, so every failure names the same commit",
        NIGHTLY, "          fetch-depth: 0", "          fetch-depth: 1", "W10", "workflows",
    ),
    Mutation(
        "the job may run longer than the liveness window allows for",
        NIGHTLY, "    timeout-minutes: 220", "    timeout-minutes: 400", "W14", "workflows",
    ),
]


def stage(scratch: Path) -> None:
    for relative in COPIED:
        target = scratch / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(REPO_ROOT / relative, target)


def run_verify(scratch: Path, half: str) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, str(scratch / ".github" / "scripts" / "tests" / "verify.py")],
        capture_output=True, text=True, timeout=600, check=False,
        env={**dict(__import__("os").environ), "NIGHTLY_ONLY": half},
    )
    return result.returncode, result.stdout + result.stderr


def failed_labels(output: str) -> list[str]:
    return [
        line.strip()[len("FAIL "):].strip()
        for line in output.splitlines()
        if line.strip().startswith("FAIL ")
    ]


def parses(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".py":
        try:
            ast.parse(text)
        except SyntaxError:
            return False
        return True
    try:
        import yaml
    except ImportError:
        # No parser, so this safeguard cannot run. Say so rather than passing silently.
        print("  note: PyYAML is absent, so mutated workflows are not parse-checked")
        return True
    try:
        yaml.safe_load(text)
    except yaml.YAMLError:
        return False
    return True


def main() -> int:
    ok = 0
    bad: list[tuple[str, str]] = []

    with tempfile.TemporaryDirectory() as tmp:
        baseline = Path(tmp) / "baseline"
        stage(baseline)
        for half in ("collector", "poster", "workflows"):
            code, output = run_verify(baseline, half)
            if code != 0:
                print(f"INVALID: the unmutated copy is already failing the {half} half")
                print(output[-2000:])
                return 2
        print(f"baseline green for all three halves ({len(MUTATIONS)} mutations to apply)\n")

        for mutation in MUTATIONS:
            scratch = Path(tmp) / "scratch"
            if scratch.exists():
                shutil.rmtree(scratch)
            stage(scratch)
            target = scratch / mutation.path

            text = target.read_text(encoding="utf-8")
            occurrences = text.count(mutation.anchor)
            if occurrences != 1:
                bad.append((mutation.name, f"anchor matched {occurrences} times in {mutation.path}"))
                print(f"  INVALID {mutation.name}")
                continue

            target.write_text(text.replace(mutation.anchor, mutation.replacement), encoding="utf-8")
            if not parses(target):
                bad.append((mutation.name, f"the mutated {mutation.path} no longer parses"))
                print(f"  INVALID {mutation.name}")
                continue

            code, output = run_verify(scratch, mutation.half)
            labels = failed_labels(output)
            hit = [label for label in labels if label.split()[0] == mutation.expect]
            if code != 0 and hit:
                ok += 1
                print(f"  caught  {mutation.name}\n            by {hit[0][:90]}")
            elif code != 0:
                bad.append((
                    mutation.name,
                    f"turned the run red, but {mutation.expect} passed. Failed instead: "
                    f"{'; '.join(labels)[:200]}",
                ))
                print(f"  MISSED  {mutation.name}")
            else:
                bad.append((mutation.name, f"{mutation.expect} did not notice; nothing failed"))
                print(f"  MISSED  {mutation.name}")

    print()
    for name, why in bad:
        print(f"  FAILED {name}\n           {why}")

    if not ok and not bad:
        print("  FAILED: no mutations ran at all")
        return 1

    print(f"\n{ok} caught, {len(bad)} not caught")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
