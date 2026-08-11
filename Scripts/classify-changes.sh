#!/usr/bin/env bash
#
# Reports which paths a change touches, and which of them carry an edit of their
# own rather than formatter output.
#
#   ./Scripts/classify-changes.sh main HEAD
#   ./Scripts/classify-changes.sh main HEAD >> "$GITHUB_STEP_SUMMARY"
#
# A branch that runs `swiftformat .` puts hundreds of files in the diff, and a
# reviewer cannot see from the file count which of them changed what the code
# does. Each file under Sources/ is taken as it was at the base, run through the
# formatter, and compared against its head version. An exact match means the
# whole change is what the formatter would have produced.
#
# This reports and never judges. It writes Markdown, exits 0 whatever it finds,
# and nothing here is a gate.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF="${1:?usage: $0 <base-ref> <head-ref>}"
HEAD_REF="${2:?usage: $0 <base-ref> <head-ref>}"

cd "$REPO_ROOT"

# The fork point, so a base branch that moved on does not show up as this
# change's work.
BASE=$(git merge-base "$BASE_REF" "$HEAD_REF" 2>/dev/null) || BASE="$BASE_REF"
HEAD_SHA=$(git rev-parse "$HEAD_REF")

echo "## Change report"
echo
echo "\`$(git rev-parse --short "$BASE")…$(git rev-parse --short "$HEAD_SHA")\`"
echo

TOTAL=$(git diff --name-only "$BASE..$HEAD_SHA" | wc -l | tr -d ' ')
echo "$TOTAL files changed."
echo

echo "### Where"
echo
echo "| Area | Files |"
echo "| --- | ---: |"
git diff --name-only "$BASE..$HEAD_SHA" \
    | awk -F/ '{ print (NF > 1 ? $1 "/" $2 : $1) }' \
    | sort | uniq -c | sort -rn \
    | awk '{ printf "| `%s` | %d |\n", $2, $1 }'
echo

# Added, deleted and renamed paths, which a file count hides.
echo "### Paths added, deleted or renamed"
echo
NOTABLE=$(git diff --name-status --find-renames "$BASE..$HEAD_SHA" | grep -vE '^M' || true)
if [ -z "$NOTABLE" ]; then
    echo "None. Every changed file already existed at the base."
else
    echo '```'
    printf '%s\n' "$NOTABLE"
    echo '```'
fi
echo

# Only Sources/ ships. Tests/ and Example/ change on purpose and are not in the
# built product.
CHANGED_SOURCES=$(git diff --name-only --diff-filter=M "$BASE..$HEAD_SHA" -- Sources/)
if [ -z "$CHANGED_SOURCES" ]; then
    echo "### Shipped code"
    echo
    echo "No file under \`Sources/\` was modified."
    exit 0
fi

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "### Shipped code"
    echo
    echo "swiftformat is not on PATH, so the formatting classification was skipped."
    echo "Modified under \`Sources/\`:"
    echo '```'
    printf '%s\n' "$CHANGED_SOURCES"
    echo '```'
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pure=0
edited=""
while IFS= read -r path; do
    [ -n "$path" ] || continue
    mkdir -p "$WORK/$(dirname "$path")"
    git show "$BASE:$path" > "$WORK/$path" 2>/dev/null || continue
    swiftformat "$WORK/$path" --config "$REPO_ROOT/.swiftformat" --quiet >/dev/null 2>&1
    git show "$HEAD_SHA:$path" > "$WORK/head-version" 2>/dev/null || continue
    if cmp -s "$WORK/$path" "$WORK/head-version"; then
        pure=$((pure + 1))
    else
        lines=$(diff "$WORK/$path" "$WORK/head-version" | grep -cE '^[<>]')
        edited="${edited}${lines}	${path}"$'\n'
    fi
done <<< "$CHANGED_SOURCES"

edited_count=$(printf '%s' "$edited" | grep -c . || true)

echo "### Shipped code (\`Sources/\`)"
echo
echo "| | Files |"
echo "| --- | ---: |"
echo "| Formatter output only, no edit of its own | $pure |"
echo "| Carry an edit of their own | $edited_count |"
echo

if [ "$edited_count" -gt 0 ]; then
    echo "These are the files to read. The count is lines that differ once formatting"
    echo "is accounted for, and it counts a comment the same as a statement."
    echo
    echo "| Changed lines | File |"
    echo "| ---: | --- |"
    printf '%s' "$edited" | sort -rn | awk -F'\t' 'NF == 2 { printf "| %s | `%s` |\n", $1, $2 }'
fi
