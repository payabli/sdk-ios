# Nightly reporter tests

`nightly_report.py` decides the nightly's verdict and gates the run. `nightly_slack.py` is the only thing
that reports a failure. Neither is covered by the SDK's own suites, and both are the kind of code whose
defects are invisible: a reporter that stops noticing something looks exactly like a repository where that
thing stopped happening.

Two entry points, both standard library only, both run by `.github/workflows/scripts.yml` on any pull
request that touches the scripts or the nightly.

```bash
python3 .github/scripts/tests/verify.py     # do the scripts behave
python3 .github/scripts/tests/sabotage.py   # would the checks notice if they stopped
```

## verify.py

83-odd named checks in three families, printed one per line.

**Collector checks (`C*`)** run `nightly_report.py` as a subprocess inside a synthetic git repository. It
globs for source files, resolves paths against its own repository root and shells out to `xcrun`, none of
which an in-process test exercises: importing it would run it against this repository's real tree and real
history, which change under the test. A stub `xcrun` earlier on `PATH` reads JSON fixtures out of the fake
result bundle, so the subprocess call, the argument shape, the JSON decode and every failure path are real,
and the harness runs on a machine with no Xcode, which is what the CI job has.

A fake bundle is a directory holding `summary.json`, `tests.json` and `xccov.json`. Leaving one out is how
the harness produces a bundle that cannot be read.

**Poster checks (`P*`)** run `nightly_slack.py` in-process against a fake Slack on loopback. It posts twice
and the second call depends on the first one's `ts`, so a stub returning canned values without being a
server would not exercise the contract that matters. The same server answers the GitHub Actions endpoints,
and `commits_since_last_green()` is driven through it for each answer it has to tell apart: a re-run of the
commit that went green, a checkout behind the baseline, a real range, rewritten history, a compare truncated
at its page limit, a branch with no previous success, and no token at all. Those decide whether a commit is
named as a probable cause, so getting one wrong blames somebody for work that was already green.

**Workflow checks (`W*`)** parse `nightly.yml` and `scripts.yml` and assert what the files have to be:
which triggers the nightly may carry, that exactly one job names the Slack token, how the liveness owner is
decided, that every suite continues on error and is bounded, that the gate reads every outcome, and that
this harness runs on every file it makes claims about. Each of those was true of how the files were
written, which is not the same as being enforced.

Set `NIGHTLY_ONLY` to `collector`, `poster` or `workflows` to run one family. The default is all three.

## sabotage.py

Breaks each guarantee in turn, in copies under a scratch directory, and confirms a named check goes red.
Nothing in the working tree is written, so an interrupted run leaves nothing behind.

Three safeguards, and each has a job:

- **An anchor must match exactly once**, so a mutation cannot silently apply somewhere else or nowhere.
- **The mutated file must still parse**, so a check going red proves the behaviour changed rather than that
  the file stopped loading.
- **The unmutated copy must be green first**, so a mutation cannot be credited with a failure that was
  already there.

A mutation whose anchor no longer matches reports `INVALID` and fails the run. Re-point it in the same
change that moved the code. Deleting the row is how coverage disappears quietly.

### What it has already caught

Worth recording, because each was live in a harness whose own run was fully green:

- **An assertion that raised instead of failing.** Reading a message the poster never sent threw
  `IndexError`, which aborted the run before a single `FAIL` line was printed and left every later check
  silently not run. On a terminal that reads exactly like passing. Every accessor into a recorded call now
  returns a default rather than raising.
- **A check satisfied by an unrelated substring.** The two fallback checks asserted `"no report"` appeared
  in the message, and the coverage line says `no report written` for a module whose report is missing. Both
  passed against a normally rendered summary, so neither could see the fallback stop happening.
- **A check weaker than the thing it guarded.** The path filter was asserted across the union of the two
  events, so removing the nightly from the `pull_request` half left it green while the guard stopped
  running on the pull request that changes it.
- **Dead code in the collector.** A flag distinguishing an unreadable bundle from an absent one could never
  change the verdict, because both produce a zero total. It was removed rather than given a check.

## Adding to either

A new behaviour in the reporter gets a check in `verify.py` and a mutation in `sabotage.py` that the check
catches. One without the other is half of the guarantee: a check nothing can break is not evidence, and a
mutation nothing catches is a gap that has been written down rather than closed.
