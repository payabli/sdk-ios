#!/usr/bin/env python3
"""Render the nightly facts into Slack: a summary in the channel, the failure detail in its thread.

A port of `.github/scripts/nightly_slack.py` in `payabli/sdk-android`, which this repository's nightly
reports alongside in one channel. The two are kept deliberately alike so a reader can tell at a glance
which platform a message came from and nothing else; compare against that file before changing anything
here, because a divergence in the message shape is a divergence in what the channel means. The Slack user
mentions that file supports are not ported: the culprit is a labelled heuristic, and the version of this
that pings people at 3am needs a team decision rather than a flag.

Runs in a job of its own that `needs` the test job. It reads the facts file `nightly_report.py` wrote and
posts twice.

Why a bot token rather than an incoming webhook. Threading needs the parent message's `ts` as `thread_ts`,
and a webhook's response body is the literal string `ok` with no `ts` and no channel, so a webhook cannot
reply to its own message. `chat.postMessage` returns `{"ok": true, "channel": ..., "ts": ...}`.

Two calls, not one, and that is not a compromise. No Slack method posts a parent and a reply together:
`thread_ts` has to name a message that already exists. Posting the summary first is also the failure mode
worth having. If the thread post fails the summary is already in the channel with the verdict, the counts
and the coverage, so the channel keeps the actionable part and loses only the detail. An atomic call would
be all or nothing, which on a red night means no message at all.

Nothing here can fail the run. A Slack outage must not turn a green nightly red, and the suite gate in the
test job owns the run result, so every path below warns and exits zero.

Never prints the token, and never renders a failure message. Those quote the operands of a failed
assertion, and the suites here assert over card numbers, CVVs, expiries, cardholder names and ACH account
numbers, so the message stays in the job summary inside GitHub and this links to it.
"""

from __future__ import annotations

import http.client
import itertools
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# Everything a call to Slack is allowed to do other than answer. `http.client.HTTPException` earns its place
# by not being an OSError: `IncompleteRead` and `BadStatusLine` are raised on a truncated or malformed
# response and urllib does not wrap them, so a handler built from URLError and OSError alone lets them
# through and the poster dies with a traceback. issubclass(HTTPException, OSError) is False.
UNREACHABLE = (
    urllib.error.URLError,
    http.client.HTTPException,
    TimeoutError,
    json.JSONDecodeError,
    OSError,
)

SLACK_API = "https://slack.com/api"
# Slack hard-limits a text block at 3000 characters. Two separate bounds therefore apply to the failure
# list, a count and a length, and both must announce themselves: a silently truncated list reads as "that
# was all of them". The length bound sits under 3000 to leave room for the notice that reports it.
INAPPLICABLE = {"line": "no lines"}
MAX_LISTED_FAILURES = 12
SLACK_BLOCK_LIMIT = 2900
SUPPORTED_SCHEMA = 4

# The dead-man's switch. A green nightly says nothing, which means silence can no longer be read as health:
# "green" and "the workflow stopped firing" would look identical, and there are documented ways to stop
# silently. This repository is public, so "scheduled workflows are automatically disabled when no repository
# activity has occurred in 60 days" applies and GitHub documents no notification when it happens; and "if the
# load is sufficiently high enough, some queued jobs may be dropped". Neither produces an error to report.
#
# So the scheduled run on the default branch arms a message in Slack's own future and cancels the one the
# previous scheduled run armed. If that nightly stops for any reason, nobody cancels it and Slack posts it.
# The clock lives outside GitHub, which is the whole point: a watcher hosted on the thing it watches dies
# with it. That is also why this is not a weekly digest job.
#
# Only that run, and see owns_liveness_switch() for why. A manual dispatch or a probe branch reports normally
# and leaves the alarm untouched, because the switch answers "is the schedule alive" and those runs are not
# evidence of a schedule. A non-owner going quiet is the design, not a broken path.
#
# 26 hours rather than 25, because a scheduled run fires some tens of minutes after the cron under the
# documented load delay, and a tighter window would cry wolf nightly.
SWITCH_HOURS = 26

# The stale sweep pages through the pending list, because an alarm it never sees is an alarm it cannot
# cancel, and that one fires as a false alarm. Bounded so a repeating or malformed cursor cannot spin: ten
# pages is 1000 pending messages, where the steady state is one or two, so exhausting this is a symptom and
# gets said out loud rather than truncated silently.
SWITCH_PAGE_SIZE = 100
MAX_SWITCH_PAGES = 10


# Marks the bot's own armed message so a future reader knows what it is, and so the cancel can tell its own
# alarms from anything else scheduled in the channel.
#
# Scoped by platform, because both platform SDKs report into this one channel. An unscoped marker would make
# an iOS alarm and an Android alarm indistinguishable, so each would cancel the other's and each would mask
# the other's death. That is worse than having no switch, because it looks like one is present. Neither
# marker may be a substring of the other, for the same reason.
def switch_marker() -> str:
    return f"nightly-liveness:{platform_name()}"


def warn(message: str) -> None:
    print(f"::warning::{message}")


def mrkdwn(text: str) -> str:
    """Escape text that came from a test result before it reaches a Slack block.

    Two reasons, and the second is the serious one. Slack mrkdwn treats `&`, `<` and `>` specially, and an
    XCTest failure is written as `("a") is not equal to ("b")` with the operands rendered verbatim, so
    ordinary assertion output would misrender. And Slack control sequences are written the same way, so an
    assertion message or a test name containing `<!channel>` would broadcast to everyone in the channel.
    Test data is untrusted input here, even when we wrote the test.
    """
    escaped = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    # Backticks are not escapable in mrkdwn, and several of these values are rendered inside a code span, so
    # one would end the span early. With the angle brackets already neutralised that is cosmetic rather than
    # a broadcast route, but the substitution costs nothing and closes the class. An apostrophe rather than a
    # deletion, so a test name that legitimately contains one still reads.
    return escaped.replace("`", "'")


def slack_post(method: str, token: str, payload: dict) -> dict | None:
    """Call one Slack Web API method. Returns the parsed body, or None if it could not be reached.

    Slack reports application errors as HTTP 200 with `{"ok": false, "error": "..."}` rather than as a
    status code, so `ok` is what the callers check. Only the error code is ever logged: the response body
    echoes the message back and the request carries the token, and neither belongs in a public log.
    """
    request = urllib.request.Request(
        f"{SLACK_API}/{method}",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {token}",
        },
        method="POST",
    )
    try:
        # Bounded on purpose. An unbounded call against a stalled endpoint would hold this job until its
        # timeout, and a Slack outage must not cost anything but the report.
        with urllib.request.urlopen(request, timeout=20) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        # 429 and 5xx arrive here. Not retried: the report is worth one attempt, and a second one on a red
        # night delays nothing that matters while adding a path that is never exercised.
        warn(f"Slack {method} returned HTTP {error.code}. The suite result is unaffected.")
        return None
    except UNREACHABLE as error:
        warn(f"Slack {method} could not be reached ({type(error).__name__}). The suite result is unaffected.")
        return None

    if not body.get("ok"):
        warn(f"Slack {method} refused the call: {body.get('error', 'unknown error')}.")
    return body


def slack_get(method: str, token: str, params: dict) -> dict | None:
    """GET one Slack Web API method. Same warn-and-return-None contract as slack_post."""
    request = urllib.request.Request(
        f"{SLACK_API}/{method}?{urllib.parse.urlencode(params)}",
        headers={"Authorization": f"Bearer {token}"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        warn(f"Slack {method} returned HTTP {error.code}. The suite result is unaffected.")
        return None
    except UNREACHABLE as error:
        warn(f"Slack {method} could not be reached ({type(error).__name__}). The suite result is unaffected.")
        return None
    if not body.get("ok"):
        warn(f"Slack {method} refused the call: {body.get('error', 'unknown error')}.")
    return body


def merge_by_commit(culprits: list[dict]) -> list[tuple[dict, list[str]]]:
    """Group attributions that name the same commit, preserving the order they were found in.

    The collector looks up two things, the failing test and the type it names, and a commit that changed a
    type usually changed its test in the same breath. Left ungrouped that renders the same sha, subject and
    author twice per failure, which on a multi-failure night is most of the message.
    """
    merged: dict[str, tuple[dict, list[str]]] = {}
    for commit in culprits:
        sha = commit.get("sha", "")
        if sha in merged:
            merged[sha][1].append(commit["what"])
        else:
            merged[sha] = (commit, [commit["what"]])
    return list(merged.values())


def trusted_run_links() -> dict[str, str]:
    """The run and commit URLs, rebuilt from this job's own environment rather than read from the facts.

    The facts file crosses a job boundary, so every value in it is untrusted input. A URL is the worst place
    for that: it is interpolated inside Slack's `<url|label>` syntax, where a single `>` closes the link and
    whatever follows is parsed as mrkdwn, so `<!channel>` in a tampered `run.url` would broadcast from the
    job that holds the bot token.

    Escaping would not be the right answer even though it would work. GitHub injects GITHUB_SERVER_URL,
    GITHUB_REPOSITORY, GITHUB_RUN_ID and GITHUB_SHA into this job directly, they describe the same run, and
    a value that never crossed the boundary cannot have been tampered with. So the dependency is removed
    rather than sanitised.
    """
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    sha = os.environ.get("GITHUB_SHA", "")[:7]
    ref = os.environ.get("GITHUB_REF_NAME", "")
    return {
        "url": f"{server}/{repo}/actions/runs/{run_id}" if repo and run_id else f"{server}/{repo}/actions",
        "commit_url": f"{server}/{repo}/commit/{sha}" if repo and sha else "",
        "sha": sha,
        "ref": ref,
    }


def summary_blocks(facts: dict, job_result: str = "success",
                   since_green: dict | None = None) -> tuple[list[dict], str]:
    """The channel message: verdict, counts, coverage, and where to look. No failure detail.

    Deliberately silent about the thread. Slack renders its own reply count on a threaded parent, so a line
    claiming detail is in the thread would be redundant when the thread post succeeds and a lie when it
    fails. Letting Slack's own affordance be the pointer keeps the parent true either way.
    """
    # The verdict is reconciled against the job result rather than trusted on its own, because the facts are
    # uploaded two steps before the gate runs. If the test job hits its own timeout during an upload or
    # during the gate, the artifact already holds a green verdict while the run is red, and posting that
    # green is exactly the run-versus-notification disagreement this workflow exists to prevent. A tampered
    # collector reaches the same place from the other direction: it can write `green` into the facts, but it
    # cannot make a failed step report success, so the gate still fails the job and the mismatch shows here.
    #
    # Anything other than a successful test job means the run is not green, whatever the artifact says, and
    # the run is the authority. The counts are still worth printing, so this corrects the headline rather
    # than discarding the message.
    claimed_red = facts["verdict"] == "red"
    unfinished = job_result != "success"
    red = claimed_red or unfinished
    verdict = "Nightly failed" if red else "Nightly green"
    icon = ":red_circle:" if red else ":white_check_mark:"
    # The ref and sha live in the context line at the bottom, not here. A branch name can be 60 characters
    # of ticket slug, which pushes the thing you actually need to read off the first line.
    lines = [f"{icon} *{mrkdwn(facts['platform'])} · {verdict}*"]
    for suite in facts["suites"]:
        lines.append(f"*{mrkdwn(suite['name'])}* {mrkdwn(suite['label'])}")

    # Four states, four phrasings, because conflating them misreports. "no code yet" is a target with
    # nothing to measure; "no report written" is a target whose coverage did not reach the bundle, which on
    # a red night is the normal fate of the target whose tests just failed. Rendering the second as the
    # first, or omitting it, would say coverage is absent when it is merely unmeasured tonight.
    #
    # Targets sharing a phrase are named together, because most nights several entries are the same words
    # repeated. A percentage never shares, since it is a fact about one target.
    #
    # Grouping is over *consecutive* targets only, so the collector's order survives and the line reads the
    # same way every night. A mixed night therefore renders each state where it falls, rather than sorting
    # targets into state buckets. Predictable beats tidy for something read at a glance at 3am.
    for group in facts["coverage"]:
        # The raw label keys the fixed-phrase lookup; the escaped one is the only form that gets rendered.
        # Both are values from the artifact, so neither reaches a block unescaped.
        label = group["label"]
        safe_label = mrkdwn(label)
        cells: list[tuple[str, str, bool]] = []
        for module in group["modules"]:
            name = mrkdwn(module["module"])
            state = module.get("state")
            percent = module.get("percent")
            # isinstance rather than a bare format, because a `:.1f` against a non-number raises and the
            # poster would die with a traceback instead of reporting. Everything here crossed the artifact.
            if state == "measured" and isinstance(percent, (int, float)):
                cells.append((name, f"{percent:.1f}%", False))
            elif state == "empty":
                cells.append((name, "no code yet", True))
            elif state == "inapplicable":
                cells.append((name, INAPPLICABLE.get(label, "no " + safe_label + " data"), True))
            else:
                cells.append((name, "no report written", True))

        rendered = []
        for (shareable, phrase), run in itertools.groupby(cells, key=lambda cell: (cell[2], cell[1])):
            names = [name for name, _, _ in run]
            if shareable:
                rendered.append(", ".join(names) + f" {phrase}")
            else:
                rendered.extend(f"{name} {phrase}" for name in names)
        measured = " · ".join(rendered) if rendered else "no targets configured"
        lines.append(f"*Coverage ({safe_label})* {measured}")

    failures = facts["failures"]
    if failures:
        lines.append(f"*Failures* {len(failures)}")

    # The bounded suspect set, next to the per-file heuristic rather than replacing it. Absent when the
    # answer would be a guess, because a missing line is better than a wrong range.
    #
    # Also absent when the comparison came out empty, where the range is real and says nothing: a span from
    # a commit to itself, or backwards from a newer baseline, over a count of zero. The thread reply is
    # where an empty comparison is worth reading, because there it names the files nobody can be blamed for.
    if since_green and not since_green.get("empty"):
        count = since_green.get("count")
        span = f"{mrkdwn(since_green['base'])}...{mrkdwn(since_green['head'])}"
        commits = f"{count} commit{'s' if count != 1 else ''}" if isinstance(count, int) else "the commits"
        lines.append(f"*Since the last green nightly* {commits} · <{since_green['url']}|{span}>")
    if unfinished and not claimed_red:
        # Named explicitly, because "collected green, ran red" is the one combination a reader would
        # otherwise have to reconcile themselves, and the run is what to believe.
        lines.append(
            f"_The collected results were green, but the test job ended `{mrkdwn(job_result)}`, so the run "
            "did not finish. Believe the run._"
        )

    blocks: list[dict] = [{"type": "section", "text": {"type": "mrkdwn", "text": "\n".join(lines)}}]

    # Traceability, kept small and out of the headline. The sha is a link so it stays one short token.
    #
    # The ref is escaped like everything else dynamic. Git allows backticks and angle brackets in a refname,
    # and a manual dispatch chooses the ref, so an unescaped one could close this code span and inject a
    # Slack control sequence.
    run = trusted_run_links()
    trail = f"<{run['url']}|Open the run>"
    if run["sha"] and run["commit_url"]:
        trail += f" · <{run['commit_url']}|`{mrkdwn(run['sha'])}`>"
    if run["ref"]:
        trail += f" on `{mrkdwn(run['ref'])}`"
    blocks.append({"type": "context", "elements": [{"type": "mrkdwn", "text": trail}]})

    # Escaped like everything else from the facts. The fallback is Slack's notification text and is rendered
    # as mrkdwn, so a `<!channel>` reaching it broadcasts even though every visible block escapes its fields.
    suite_text = ", ".join(f"{mrkdwn(s['label'])} {mrkdwn(s['name']).lower()}" for s in facts["suites"])
    # `verdict` rather than the artifact's own, so the notification agrees with the headline above it.
    return blocks, f"{mrkdwn(facts['platform'])} {verdict.lower()}: {suite_text}"


def landed_before_last_green(commit: dict, since_green: dict | None) -> bool:
    """Whether a culprit commit was already in the tree the last time the suite was green.

    The per-file culprit is `git log -1 -- <file>`, which answers who touched a file last and not what
    changed. For a file nobody has touched in weeks it names a commit that has passed every nightly since,
    and it names its author beside a failure they cannot have caused. The range the summary already reports
    is what settles it, so the thread says the files have not changed since the last green run rather than
    naming somebody.

    False whenever the range is unknown or partial, which keeps the fallback at the sentence this reporter
    would otherwise print rather than at a claim the data does not support.
    """
    shas = (since_green or {}).get("shas")
    short = str(commit.get("sha", ""))
    # `is None` rather than falsy, which is the difference between a comparison that could not be made and
    # one that came out empty. An empty list is the case where nothing landed since the last green run, so
    # every culprit is outside the range and none of them is a suspect; reading it as unknown puts the blame
    # back on precisely the runs that are flakes by definition.
    if shas is None or not short:
        return False
    return not any(full.startswith(short) for full in shas)


def thread_blocks(facts: dict, since_green: dict | None = None) -> list[dict]:
    """The thread reply: one entry per failed test, with its trace linked and its commit attributed.

    The failure text is a link rather than the text itself, and that is a disclosure boundary rather than
    a length one. XCTest writes a mismatch as both operands quoted, and the suites here assert over card
    numbers, CVVs, expiries, cardholder names and ACH account numbers, so the first line of a failing
    payment assertion carries exactly the fields that must never be logged. Nothing renders it here: the
    job summary holds it, inside GitHub, and this links there.
    """
    failures = facts["failures"]
    run_url = trusted_run_links()["url"]

    # One rendered entry per failure, so trimming can drop whole failures rather than cut through one.
    entries: list[str] = []
    for failure in failures[:MAX_LISTED_FAILURES]:
        # Every field here originates in a test result or in git output, which carries commit subjects and
        # author names, so all of it is escaped.
        # The label and the link, never the failure message itself. An XCTest mismatch quotes both
        # operands, and this repository's suites assert over card numbers, CVVs, expiries, cardholder
        # names and ACH account numbers, so a failing payment assertion would copy those fields into
        # Slack storage, in a channel, permanently. The message is in the job summary, which is inside
        # GitHub with the same audience as the logs, and that is what the link goes to.
        entry = f"\n• `{mrkdwn(failure['label'])}` · <{run_url}|failure message>"
        for commit, whats in merge_by_commit(failure["culprits"]):
            # One line per commit, not per lookup. The two lookups usually land on the same commit, because
            # a change to a type and to its test normally ships together, and printing that commit twice
            # with only the leading noun different was the least readable thing in the message.
            subjects = " and ".join("test" if what == "test" else f"`{mrkdwn(what)}`" for what in whats)
            if landed_before_last_green(commit, since_green):
                # No author, and that is the finding rather than a saving. The author travels with a culprit
                # because a name beside a commit is the cheapest route to the person who knows; the author
                # of a commit that has been green for a week is not that person.
                entry += (
                    f"\n  {subjects} unchanged since the last green nightly "
                    f"`{mrkdwn(str((since_green or {}).get('base', '')))}`"
                )
                continue
            author = mrkdwn(commit.get("author", "")) or "unknown author"
            entry += (
                f"\n  {subjects} last touched by `{mrkdwn(commit['sha'])}"
                f" {mrkdwn(commit['subject'])}` — {author}"
            )
        entries.append(entry)

    # Two independent limits, and the character one must not be applied by slicing the finished string.
    # Twelve failures at 300 characters each exceed the block limit before any culprit text, so the list
    # would be cut mid-failure while the omitted count stayed zero and the message therefore claimed to be
    # complete. Drop whole entries until the text and its notice fit, and always say how many are missing,
    # counting both limits together.
    #
    # Drops to zero entries if it has to. Stopping at one leaves the contract broken in the case it is meant
    # to cover: a single entry longer than the limit, from a long test name or commit subject, sliced
    # mid-entry with no notice. Header plus notice is always short enough.
    while True:
        hidden = len(failures) - len(entries)
        notice = f"\n_{hidden} further failure(s) not listed here; see the run._" if hidden else ""
        header = "*Probable cause is a heuristic, not evidence.*"
        text = f"{header}" + "".join(entries) + notice
        if len(text) <= SLACK_BLOCK_LIMIT or not entries:
            break
        entries.pop()

    return [{"type": "section", "text": {"type": "mrkdwn", "text": text[:SLACK_BLOCK_LIMIT]}}]


# What a malformed artifact raises on the way through a renderer. Narrow on purpose: these are shape errors,
# not a licence to swallow a defect in the rendering code, and every one of them is warned about loudly.
SHAPE_ERRORS = (KeyError, IndexError, TypeError, ValueError, AttributeError)


def usable_facts(raw: object) -> dict | None:
    """The facts if they are the shape this poster renders, otherwise None.

    Matching the schema number is not the same as being usable, and the gap is reachable: `{"schema": 4}`
    passes the version check and then raises KeyError on `verdict`, and a JSON list root raises
    AttributeError on `.get` before any check runs. Either way the poster would die before posting even the
    no-report fallback, so a tampered or truncated artifact would turn into a silent channel, which is the
    outcome this reporter exists to make impossible.

    Only the root shape is asserted here. Nested fields are covered by catching SHAPE_ERRORS around
    rendering, because enumerating every nested key would duplicate the renderers and drift from them.
    """
    if not isinstance(raw, dict):
        warn(f"The nightly facts are {type(raw).__name__}, not an object, so they cannot be rendered.")
        return None
    if raw.get("schema") != SUPPORTED_SCHEMA:
        warn(f"Unsupported nightly facts schema {raw.get('schema')!r}; expected {SUPPORTED_SCHEMA}.")
        return None
    required = {"verdict": str, "platform": str, "suites": list, "coverage": list, "failures": list}
    for key, kind in required.items():
        if not isinstance(raw.get(key), kind):
            warn(f"The nightly facts are missing a usable {key!r}, so they cannot be rendered.")
            return None
    return raw


def github_get(url: str, token: str) -> dict | None:
    """GET one GitHub API URL. Warns and returns None rather than raising, like the Slack helpers."""
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        warn(f"GitHub API returned HTTP {error.code} for a last-green lookup. The report continues without it.")
        return None
    except UNREACHABLE as error:
        warn(f"GitHub API unreachable for a last-green lookup ({type(error).__name__}).")
        return None


def commits_since_last_green() -> dict | None:
    """The commit range between the last successful nightly on this branch and this one.

    Replaces guesswork with a bounded fact. The per-file culprit is `git log -1 -- <file>`, a heuristic that
    can be wrong; the honest suspect set is everything that landed since the suite was last known good, and
    only the Actions API knows when that was.

    Runs here, in the report job, rather than in the collector. The query needs a token, and no git history
    is needed either way: the baseline is a sha from the API and the compare link is just two shas.

    A successful run is the right definition of green, because the suite gate is what decides that run's
    conclusion, so this cannot disagree with the verdict the way a separate judgement would.

    Returns None whenever the answer would be a guess: no token, no previous success on this branch, or an
    API that would not answer. The report is better without the line than with a wrong one.
    """
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    sha = os.environ.get("GITHUB_SHA", "")
    branch = os.environ.get("GITHUB_REF_NAME", "")
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    if not (token and repo and run_id and sha):
        return None

    # The workflow id comes from this run rather than from a hardcoded filename, so renaming the file cannot
    # quietly turn this into a lookup against the wrong workflow.
    this_run = github_get(f"{api}/repos/{repo}/actions/runs/{run_id}", token)
    workflow_id = (this_run or {}).get("workflow_id")
    if not workflow_id:
        return None

    query = urllib.parse.urlencode(
        {"status": "success", "per_page": 20, **({"branch": branch} if branch else {})}
    )
    listed = github_get(f"{api}/repos/{repo}/actions/workflows/{workflow_id}/runs?{query}", token)
    baseline = None
    for candidate in (listed or {}).get("workflow_runs") or []:
        # Newest first, so the first success that is not this run is the last known good one.
        if str(candidate.get("id")) != str(run_id) and candidate.get("head_sha"):
            baseline = candidate
            break
    if not baseline:
        return None

    base_sha = baseline["head_sha"]
    facts = {
        "base": base_sha[:7],
        "head": sha[:7],
        "url": f"{server}/{repo}/compare/{base_sha}...{sha}",
        "when": baseline.get("created_at", ""),
    }
    if base_sha == sha:
        # This is the commit that went green, so nothing landed since. `empty` rather than None, and the
        # distinction is the whole point of the two keys: None means the comparison could not be made, while
        # an empty sha list is a comparison that came out empty. Returning None here would make a re-run of a
        # green commit fall back to naming whoever last touched the file, which is the case with the
        # strongest possible evidence that nobody is to blame.
        return {**facts, "count": 0, "shas": [], "empty": True}

    compared = github_get(f"{api}/repos/{repo}/compare/{base_sha}...{sha}", token)
    status = (compared or {}).get("status")
    total = (compared or {}).get("total_commits")

    # `behind` means this checkout is an ancestor of the baseline and `identical` means it is the baseline,
    # so under either one every commit here was already in the tree that went green. Both also report
    # `total_commits` 0, which is why a count cannot be read as ancestry. Re-running an older failure after a
    # newer success produces the reversed case.
    if status in ("behind", "identical"):
        return {**facts, "count": 0, "shas": [], "empty": True}

    # `ahead` is the only remaining status under which "commits since the last green nightly" is a true
    # description. `diverged` carries a real count over rewritten history, where it counts commits since
    # nothing, so ancestry there is unknown rather than empty and the attribution falls back accordingly.
    if status != "ahead":
        return None
    if not isinstance(total, int):
        # The compare did not answer, which happens when a force-push leaves the previous success
        # incomparable. The link would 404 as well, so rendering a suspect range here would be a guess with
        # a dead reference attached. This function's contract is to return nothing rather than that.
        return None
    return {**facts, "count": total, "shas": range_shas(compared, total)}


def range_shas(compared: dict | None, total: int) -> list[str] | None:
    """Every commit in the range, or None when the answer would be a partial list.

    The compare endpoint pages its `commits` array at 250 entries while `total_commits` counts the whole
    range, so a short list is a truncated one. A truncated list cannot support the one thing this is read
    for, which is concluding that a commit is **not** in the range: every absence would be indistinguishable
    from a page that was never fetched. None rather than partial, and the reader of this value falls back
    accordingly.
    """
    listed = (compared or {}).get("commits")
    if not isinstance(listed, list):
        return None
    shas = [str(commit.get("sha", "")) for commit in listed if commit.get("sha")]
    # One guard for both ways of coming up short, a truncated page and an entry with no sha, because the
    # consequence is the same: fewer shas than the range holds, and an absence that means nothing.
    return shas if len(shas) == total else None


def arm_liveness_switch(token: str, channel: str, marker: str | None = None,
                        subject: str = "nightly") -> tuple[str, int] | None:
    """Schedule the alarm and return its id, or None if Slack would not take it.

    Armed before the previous one is cancelled, deliberately. Cancelling first would avoid a duplicate if
    the arm failed, but the two failures are not comparable: a duplicate is one false alarm, while
    cancelling and then failing to arm leaves *no* pending alarm, and a stopped nightly then becomes
    indistinguishable from green silence, which is the single thing this whole mechanism exists to prevent.
    Arming first means at least one alarm is pending at every instant, including if this job is superseded
    mid-sequence, which `cancel-in-progress` makes a live possibility.
    """
    marker = marker or switch_marker()
    post_at = int(time.time()) + SWITCH_HOURS * 3600
    platform = mrkdwn(platform_name())
    run = trusted_run_links()
    # Kept short on purpose. This is read at a glance, and what belongs in it is the three things that
    # change what someone does next: what happened, that it is worse than a red suite, and where to look.
    text = (
        f":rotating_light: *{platform} · no {mrkdwn(subject)} report in over {SWITCH_HOURS} hours*\n\n"
        "It did not run, or could not reach Slack. This is not just a red suite.\n\n"
        "Check, in order:\n"
        "1. the workflow is still enabled, since a public repo silently disables schedules "
        "after 60 days idle\n"
        "2. scheduled runs were not dropped under load\n"
        "3. the Actions service itself is healthy, at <https://www.githubstatus.com|githubstatus.com>"
    )
    blocks = [{"type": "section", "text": {"type": "mrkdwn", "text": text}}]
    if run["url"]:
        blocks.append({
            "type": "context",
            "elements": [{"type": "mrkdwn", "text": f"<{run['url']}|The last run that armed this>"}],
        })
    armed = slack_post("chat.scheduleMessage", token, {
        "channel": channel,
        "post_at": post_at,
        # The marker rides in the fallback text because that is what chat.scheduledMessages.list returns, so
        # it is what the cancel step can filter on. Without it the cancel would delete every message this bot
        # has scheduled in the channel, which is not the same set.
        "text": f"[{marker}] {platform_name()} {subject} has not reported for over {SWITCH_HOURS} hours",
        "blocks": blocks,
        # Not metadata: Slack documents that a message scheduled with the metadata parameter will not post,
        # which would disarm the switch silently.
        "unfurl_links": False,
    })
    if armed and armed.get("ok"):
        message_id = armed.get("scheduled_message_id")
        # post_at is echoed back, but the value we asked for is authoritative for the ordering comparison.
        return (message_id, post_at) if message_id else None
    return None


def cancel_stale_switches(token: str, channel: str, keep: str, keep_post_at: int,
                          marker: str | None = None) -> bool:
    """Cancel this bot's alarms that are strictly older than the one just armed, reporting whether it worked.

    Filtered on the scoped marker rather than deleting everything the token has pending. The list is scoped
    to this token, which stops the bot touching a person's scheduled message, but it does not distinguish
    the alarm from anything else this bot might ever schedule in the channel, and the sibling platform's
    alarm is in this channel too.

    Filtered on `post_at` as well. `cancel-in-progress` only *requests* cancellation, so two runs on the same
    ref can overlap. Both arm, then each lists both alarms and deletes the one that is not its own, leaving
    nothing pending while the later run still reports success. Deleting only what is strictly older is what
    closes that: every run's own alarm has the latest `post_at`, so the newest always survives no matter
    which order the two cancels interleave.

    Ties and unreadable timestamps are retained rather than deleted. Two alarms armed in the same second
    leave a duplicate, which is one false alarm and self-heals on the next run; deleting on a tie could leave
    zero, which is the outcome this whole mechanism exists to prevent.

    Paged rather than read one page deep. A single request is enough for the steady state, but the sweep is
    the only thing that removes an alarm, so anything it does not see fires.

    Returns False when a stale alarm may still be pending, whether because the list could not be read, a page
    was never reached, or a delete was refused. The caller needs that: yesterday's alarm is due about two
    hours from now, before the next nightly, so a failed sweep is a false alarm already in flight.
    """
    marker = marker or switch_marker()
    swept = True
    cursor = ""
    for _ in range(MAX_SWITCH_PAGES):
        params = {"channel": channel, "limit": SWITCH_PAGE_SIZE}
        if cursor:
            params["cursor"] = cursor
        pending = slack_get("chat.scheduledMessages.list", token, params)
        if not (pending and pending.get("ok")):
            # Nothing is known about what is pending, so the older alarm cannot be assumed gone.
            return False
        for message in pending.get("scheduled_messages") or []:
            message_id = message.get("id")
            if not message_id or message_id == keep:
                continue
            if marker not in (message.get("text") or ""):
                continue
            post_at = message.get("post_at")
            if not isinstance(post_at, int) or post_at >= keep_post_at:
                # Not provably older, so not ours to remove.
                continue
            removed = slack_post("chat.deleteScheduledMessage", token,
                                 {"channel": channel, "scheduled_message_id": message_id})
            if not (removed and removed.get("ok")):
                swept = False
        cursor = str((pending.get("response_metadata") or {}).get("next_cursor") or "").strip()
        if not cursor:
            return swept
    warn(f"More than {MAX_SWITCH_PAGES} pages of scheduled messages are pending, so the oldest alarms were "
         "not examined and one may fire spuriously.")
    return False


def owns_liveness_switch() -> bool:
    """Whether this run is the one the switch is about.

    The switch answers "is the scheduled nightly still alive", so only the scheduled nightly may reset it.
    Resetting on every run would measure something weaker and self-defeating: "somebody ran the nightly at
    some point". A dead schedule could then be masked indefinitely by the occasional manual dispatch or probe
    branch, which is precisely the failure the switch exists to catch, and the chance of that rises with the
    number of people who might dispatch it.

    A non-owning run still reports normally. It simply leaves the alarm alone rather than vouching for a
    schedule it is not evidence of.
    """
    return os.environ.get("LIVENESS_OWNER", "").strip().lower() == "true"


def reset_liveness_switch(token: str, channel: str, marker: str | None = None,
                          subject: str = "nightly") -> bool:
    """Arm a fresh alarm and clear the older ones. True only if *exactly one* alarm is now pending.

    The return value is the point. Returning nothing while the caller prints that the switch was re-armed is
    a claim the code cannot support: every call inside warns and continues, so a green night could post
    nothing *and* arm nothing, producing exactly the unmonitored silence this replaces.

    Too many pending alarms is a failure as well as too few. Arming succeeding while the sweep quietly failed
    would still count as success, and the alarm the sweep should have removed is due before the next nightly,
    so it fires and reports a stopped nightly that did not stop.
    """
    marker = marker or switch_marker()
    armed = arm_liveness_switch(token, channel, marker, subject)
    if not armed:
        warn(f"The liveness switch could not be armed, so silence would not be monitored ({marker}).")
        return False
    if not cancel_stale_switches(token, channel, keep=armed[0], keep_post_at=armed[1], marker=marker):
        # Not a smaller problem than failing to arm, just a noisier one. A false alarm is what teaches people
        # to stop believing the alarm, and an alarm nobody believes is the same as no alarm at all.
        warn(f"An earlier alarm may still be pending and fire spuriously ({marker}).")
        return False
    print(f"::notice::Liveness switch armed for {SWITCH_HOURS}h ({marker}).")
    return True


def platform_name() -> str:
    """The platform label, from the workflow rather than guessed.

    Both platform SDKs report into one channel, so a message that does not name the platform is ambiguous,
    and the no-facts path is the one place that cannot read it out of the facts file.
    """
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    return os.environ.get("PLATFORM", "").strip() or (repo.rsplit("/", 1)[-1] if repo else "Nightly")


def unreported_blocks(job_result: str) -> tuple[list[dict], str]:
    """What to say when no facts file reached this job.

    This is the case a single-job arrangement cannot report. Posting from inside the test job behind
    `if: always()` dies with the job on a timeout or a cancellation, so the channel simply goes quiet on the
    nights that most need a message. Reporting from a separate job means a dead test job still gets
    announced.

    Two different situations reach here and the message must not merge them, because an absent facts file
    does not prove the test job failed to write one. The upload and the download are both deliberately
    non-blocking, so a transient artifact-service error loses the report while the suite and the run stay
    green. Saying "the test job ended success without writing a report" in that case is both wrong and
    self-contradictory, and a red circle over a green suite is a false alarm on the one channel that exists
    to be trusted.

    The job result tells the two apart on its own. The gate lives in the test job and fails it on a red
    verdict, so `success` proves the suite passed and the results existed, which leaves the transfer as the
    only thing that can have gone wrong.
    """
    if job_result == "success":
        icon = ":warning:"
        cause = (
            "The test job passed, its suite gate included, so the results existed and the suite was green. "
            "The facts file did not reach this job. The artifact upload and download are both non-blocking, "
            "so a transient artifact-service error loses the report without touching the run result."
        )
        fallback = f"{mrkdwn(platform_name())} nightly passed but its report did not arrive"
    else:
        icon = ":red_circle:"
        cause = (
            f"The test job ended `{mrkdwn(job_result)}`, so it produced no usable report. A cancellation, a "
            "job timeout, or a failure before the tests ran each end it this way."
        )
        fallback = f"{mrkdwn(platform_name())} nightly produced no report"

    platform = mrkdwn(platform_name())
    blocks: list[dict] = [
        {"type": "section",
         "text": {"type": "mrkdwn", "text": f"{icon} *{platform} · Nightly · no report*\n{cause}"}}
    ]
    # Without a link the message names a problem and offers nowhere to go and look at it.
    if os.environ.get("GITHUB_REPOSITORY") and os.environ.get("GITHUB_RUN_ID"):
        blocks.append({
            "type": "context",
            "elements": [{"type": "mrkdwn", "text": f"<{trusted_run_links()['url']}|Open the run>"}],
        })
    return blocks, fallback


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <facts-path>", file=sys.stderr)
        return 2

    token = os.environ.get("SLACK_BOT_TOKEN", "").strip()
    channel = os.environ.get("SLACK_CHANNEL_ID", "").strip()
    # Absent credentials warn and skip, and never cost the suite result. The nightly's whole point is the
    # test outcome; the report is how it is delivered, and a delivery problem is not a test result.
    if not token or not channel:
        warn("SLACK_BOT_TOKEN or SLACK_CHANNEL_ID is not set, so no nightly report was posted.")
        return 0

    facts_path = Path(sys.argv[1])
    facts: dict | None = None
    if facts_path.is_file():
        try:
            facts = usable_facts(json.loads(facts_path.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError) as error:
            warn(f"The nightly facts file could not be read ({type(error).__name__}).")

    job_result = os.environ.get("NIGHTLY_JOB_RESULT", "success" if facts else "unknown")

    # Decided before anything is rendered, and that ordering is load-bearing rather than tidy. The
    # commit-range lookup costs up to three Actions API calls, and building the blocks first would make a
    # green night pay for all of them and throw the result away. Worse, an Actions API timeout would then
    # delay re-arming the liveness switch, which is the one thing on a green night that must not be delayed.
    green = facts is not None and facts["verdict"] != "red" and job_result == "success"
    if green and not owns_liveness_switch():
        # A dispatch or a probe. Silent because it is green, and it does not vouch for the schedule.
        print("::notice::Nightly is green, so nothing was posted. This run does not own the liveness switch.")
        return 0
    if green and reset_liveness_switch(token, channel):
        print("::notice::Nightly is green, so nothing was posted. The liveness switch is armed.")
        return 0
    if green:
        # Silence is only safe while exactly one alarm is pending, and it is not: either none could be armed,
        # or an older one survived the sweep and is due before the next nightly. Post the green summary
        # instead. Worse to read, but with nothing armed the channel at least keeps its evidence that the
        # nightly ran, and with a stale alarm in flight this is what stops the false alarm two hours from now
        # being read as a dead schedule.
        #
        # The reset below is skipped after this, because the attempt has already been made this run. Retrying
        # it would arm a second alarm within the same second as the first, and two alarms sharing a `post_at`
        # tie, which the sweep retains by design: the retry would create the duplicate the sweep refuses to
        # resolve.
        warn("Posting the green summary because silence is not covered by exactly one pending alarm.")

    # Looked up once and read twice: the summary reports the range, and the thread reply below uses it to
    # tell a culprit that landed inside it from one that has been green for a week. A second lookup would
    # spend three more Actions API calls to answer the same question.
    since_green = None
    if facts is None:
        blocks, fallback = unreported_blocks(job_result)
    else:
        try:
            # Not looked up when green, and that is both halves of the reasoning above. A green fallback
            # would otherwise pay for three Actions API calls the early decision exists to avoid, and it
            # would print a suspect range under a headline saying the nightly passed, which invites a hunt
            # for a cause that does not exist. The range answers "what might have broken it", so a green run
            # has no question.
            since_green = None if green else commits_since_last_green()
            blocks, fallback = summary_blocks(facts, job_result, since_green)
        except SHAPE_ERRORS as error:
            # Something nested is not the shape the renderer expects. Report that rather than dying, because
            # the alternative is a channel that says nothing on a night when something is already wrong.
            warn(f"The nightly facts could not be rendered ({type(error).__name__}: {error}).")
            facts = None
            blocks, fallback = unreported_blocks(job_result)

    # Reaching here means something is being posted: a red night, a night with no usable facts, or a green
    # night whose switch could not be armed. The green decision itself is above, with its reasoning.
    #
    # Stated as the invariant rather than as the sequence: **the channel is never left silent with no alarm
    # pending.** That is what the ordering below protects. The reset therefore happens only after Slack has
    # accepted the report, so a lost report cannot push the alarm out, and only for the run that owns the
    # switch, so a dispatch cannot vouch for the schedule.
    parent = slack_post("chat.postMessage", token, {"channel": channel, "text": fallback, "blocks": blocks})
    if parent is None or not parent.get("ok"):
        # Deliberately not reset here. The switch asserts that the channel heard from the nightly, and it did
        # not: resetting would push the alarm out another 26 hours while the report was lost. Leaving the
        # existing alarm armed is what makes that visible.
        return 0
    if owns_liveness_switch() and not green:
        reset_liveness_switch(token, channel)

    if facts is None or not facts["failures"]:
        return 0

    thread_ts = parent.get("ts")
    if not thread_ts:
        # Documented to be present on a successful post, so this is defensive rather than expected.
        warn("Slack accepted the summary but returned no ts, so the failure detail was not threaded.")
        return 0

    try:
        detail = thread_blocks(facts, since_green)
    except SHAPE_ERRORS as error:
        # The summary has already landed, so this costs the detail and nothing else.
        warn(f"The failure detail could not be rendered ({type(error).__name__}: {error}).")
        return 0

    slack_post(
        "chat.postMessage",
        token,
        {
            "channel": channel,
            "thread_ts": thread_ts,
            "text": f"{len(facts['failures'])} failure(s)",
            "blocks": detail,
        },
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
