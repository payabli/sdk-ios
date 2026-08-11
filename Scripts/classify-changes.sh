#!/usr/bin/env bash
#
# Sizes the review surface of a change: how much of a diff is a semantic change
# to shipped code, and how much is inert.
#
#   ./Scripts/classify-changes.sh main HEAD
#   ./Scripts/classify-changes.sh main HEAD >> "$GITHUB_STEP_SUMMARY"
#
# A branch that runs `swiftformat .` puts hundreds of files in the diff and a
# file count says nothing about what to read. Every modified file under Sources/
# is normalised by running the formatter over its base revision, so what remains
# in the diff is the author's edit. Those lines are then split into declarations,
# executable statements and comments, because only the first two can change
# behaviour and only the first can break a consumer.
#
# Reports and never judges. Writes Markdown, exits 0 whatever it finds.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF="${1:?usage: $0 <base-ref> <head-ref>}"
HEAD_REF="${2:?usage: $0 <base-ref> <head-ref>}"

cd "$REPO_ROOT"

BASE=$(git merge-base "$BASE_REF" "$HEAD_REF" 2>/dev/null) || BASE="$BASE_REF"
HEAD_SHA=$(git rev-parse "$HEAD_REF")

# The marker CI finds this comment by, so each run edits the one comment
# instead of posting another. Invisible when the Markdown renders.
echo "<!-- change-report -->"
echo "## Change report"
echo
echo "\`$(git rev-parse --short "$BASE")…$(git rev-parse --short "$HEAD_SHA")\` · $(git diff --name-only "$BASE..$HEAD_SHA" | wc -l | tr -d ' ') files"
echo

# ---------------------------------------------------------------- review surface

# Sources/ is the library that ships to consumers. Nothing else in the tree is
# linked into their app, so a change outside it cannot alter released behaviour.
classify_path() {
    case "$1" in
        Sources/*)  echo "Production code (ships in the SDK)" ;;
        Tests/*)    echo "Test code" ;;
        Example/*)  echo "Sample app" ;;
        Bridges/*)  echo "Bridge wrappers" ;;
        .github/*|Scripts/*|*.yml|*.xcconfig|.swiftformat|.swiftlint.yml|sonar-project.properties|Package.swift|.gitignore)
                    echo "Build, CI and tooling" ;;
        *)          echo "Other" ;;
    esac
}

echo "### Review surface"
echo
echo "| Category | Files |"
echo "| --- | ---: |"
while IFS= read -r path; do
    classify_path "$path"
done < <(git diff --name-only "$BASE..$HEAD_SHA") | sort | uniq -c | sort -rn \
    | sed -E 's/^ *([0-9]+) (.*)$/| \2 | \1 |/'
echo

# ------------------------------------------------------------- lifecycle of files

# A rename similarity below 100 means the file moved and was edited in the same
# commit, which a reviewer reading only the new path would miss.
echo "### Files added, deleted and renamed"
echo
LIFECYCLE=$(git diff --name-status --find-renames "$BASE..$HEAD_SHA" | grep -vE '^M' || true)
if [ -z "$LIFECYCLE" ]; then
    echo "None. Every changed file already existed at the base revision, so no"
    echo "compilation unit entered or left the build."
else
    added=$(printf '%s\n' "$LIFECYCLE" | grep -c '^A' || true)
    deleted=$(printf '%s\n' "$LIFECYCLE" | grep -c '^D' || true)
    renamed=$(printf '%s\n' "$LIFECYCLE" | grep -c '^R' || true)
    echo "$added added, $deleted deleted, $renamed renamed."
    echo
    echo '```'
    printf '%s\n' "$LIFECYCLE"
    echo '```'
    if printf '%s\n' "$LIFECYCLE" | grep -qE '^R0[0-9][0-9]' ; then
        echo
        echo "A rename shown below \`R100\` was edited as well as moved."
    fi
fi
echo

# ------------------------------------------------------------------ shipped code

# Swift only. Sources/ also carries Markdown, and prose about a public type
# reads as a declaration to a grep.
CHANGED_SOURCES=$(git diff --name-only --diff-filter=M "$BASE..$HEAD_SHA" -- Sources/ | grep '\.swift$' || true)
ADDED_SOURCES=$(git diff --name-only --diff-filter=A "$BASE..$HEAD_SHA" -- Sources/ | grep '\.swift$' || true)
DELETED_SOURCES=$(git diff --name-only --diff-filter=D "$BASE..$HEAD_SHA" -- Sources/ | grep '\.swift$' || true)
if [ -z "$CHANGED_SOURCES" ] && [ -z "$ADDED_SOURCES" ] && [ -z "$DELETED_SOURCES" ]; then
    echo "### Production code"
    echo
    echo "Nothing under \`Sources/\` changed, so released behaviour is unchanged and"
    echo "the public surface is untouched."
    exit 0
fi

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "### Production code"
    echo
    echo "swiftformat is not on PATH, so the diff could not be normalised and the"
    echo "semantic classification was skipped. Modified under \`Sources/\`:"
    echo '```'
    printf '%s\n' "$CHANGED_SOURCES"
    echo '```'
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

inert=0            # files whose entire diff the formatter would have produced
doc_only=0         # files whose remaining diff is comments and blank lines
semantic=0         # files with a changed declaration or statement
rows=""            # per-file detail for the files that carry a semantic change
doc_rows=""
api_added=""
api_removed=""

while IFS= read -r path; do
    [ -n "$path" ] || continue
    mkdir -p "$WORK/$(dirname "$path")"
    git show "$BASE:$path" > "$WORK/$path" 2>/dev/null || continue
    # Normalising the base revision is what separates the author's edit from the
    # formatter's. Without it every reformatted file looks like a rewrite.
    swiftformat "$WORK/$path" --config "$REPO_ROOT/.swiftformat" --quiet >/dev/null 2>&1
    git show "$HEAD_SHA:$path" > "$WORK/head-version" 2>/dev/null || continue

    if cmp -s "$WORK/$path" "$WORK/head-version"; then
        inert=$((inert + 1))
        continue
    fi

    changed=$(diff "$WORK/$path" "$WORK/head-version" | grep -E '^[<>]' || true)

    # Net of relocations. A line removed from one place and added unchanged in
    # another is a move, and a move compiles to what it compiled to before.
    # Counting both ends of it reports a rewrite where a block shifted.
    side() {   # $1 = < or >, $2 = keep|drop comments
        local filter='^(///|//|/\*|\*/|\*)'
        printf '%s\n' "$changed" | grep -E "^$1" | sed -E 's/^.[[:space:]]*//' \
            | if [ "$2" = drop ]; then grep -vE "$filter"; else grep -E "$filter"; fi \
            | grep -v '^[[:space:]]*$' | sed -E 's/[[:space:]]+/ /g' | sort
    }
    code=$(comm -3 <(side '<' drop) <(side '>' drop) | grep -c . || true)
    comments=$(comm -3 <(side '<' keep) <(side '>' keep) | grep -c . || true)

    # A changed declaration carrying `public` or `open` is a change to the
    # contract consumers compile against, which the repository holds in common
    # with the SDK for Android.
    added_api=$(printf '%s\n' "$changed" | grep -E '^>' | grep -E '(^|[[:space:]])(public|open)([[:space:]]|$)' || true)
    removed_api=$(printf '%s\n' "$changed" | grep -E '^<' | grep -E '(^|[[:space:]])(public|open)([[:space:]]|$)' || true)
    [ -n "$added_api" ] && api_added="${api_added}${path}"$'\n'"${added_api}"$'\n'
    [ -n "$removed_api" ] && api_removed="${api_removed}${path}"$'\n'"${removed_api}"$'\n'

    if [ "$code" -gt 0 ]; then
        semantic=$((semantic + 1))
        rows="${rows}${code}	${comments}	${path}"$'\n'
    else
        doc_only=$((doc_only + 1))
        doc_rows="${doc_rows}${comments}	${path}"$'\n'
    fi
done <<< "$CHANGED_SOURCES"

# A file that entered or left the build carries its whole contents as added or
# removed API. The classification above speaks only for modified files, so
# without this the report would call a new public type source compatible.
while IFS= read -r path; do
    [ -n "$path" ] || continue
    decls=$(git show "$HEAD_SHA:$path" 2>/dev/null \
        | grep -E '(^|[[:space:]])(public|open)([[:space:]]|$)' || true)
    [ -n "$decls" ] && api_added="${api_added}${path} (file added)"$'\n'"${decls}"$'\n'
done <<< "$ADDED_SOURCES"

while IFS= read -r path; do
    [ -n "$path" ] || continue
    decls=$(git show "$BASE:$path" 2>/dev/null \
        | grep -E '(^|[[:space:]])(public|open)([[:space:]]|$)' || true)
    [ -n "$decls" ] && api_removed="${api_removed}${path} (file deleted)"$'\n'"${decls}"$'\n'
done <<< "$DELETED_SOURCES"

modified_total=$(printf '%s\n' "$CHANGED_SOURCES" | grep -c . || true)
added_total=$(printf '%s\n' "$ADDED_SOURCES" | grep -c . || true)
deleted_total=$(printf '%s\n' "$DELETED_SOURCES" | grep -c . || true)

echo "### Production code (\`Sources/\`)"
echo
echo "$modified_total modified, $added_total added, $deleted_total deleted, classified by whether the change can alter behaviour."
echo
echo "| Classification | Files | Reviewer action |"
echo "| --- | ---: | --- |"
echo "| Formatting only, semantically inert | $inert | None. Reproduced by running the formatter over the base revision. |"
echo "| Comments and documentation only | $doc_only | Read for accuracy. Compiles to the same code. |"
echo "| Declarations or statements changed | $semantic | Review. This is where behaviour can change. |"
if [ "$added_total" -gt 0 ]; then
    echo "| Files added | $added_total | Review in full. Every line is new. |"
fi
if [ "$deleted_total" -gt 0 ]; then
    echo "| Files deleted | $deleted_total | Confirm nothing depended on them. |"
fi
echo

if [ "$semantic" -gt 0 ]; then
    echo "#### Files that can change behaviour"
    echo
    echo "\`Code\` counts declarations and executable statements that differ once"
    echo "formatting is normalised and relocations are netted out: a line moved"
    echo "without being altered compiles to what it compiled to before. \`Docs\` is"
    echo "the same count for comments."
    echo
    echo "| Code | Docs | File |"
    echo "| ---: | ---: | --- |"
    printf '%s' "$rows" | sort -rn | awk -F'\t' 'NF == 3 { printf "| %s | %s | `%s` |\n", $1, $2, $3 }'
    echo
fi

if [ "$doc_only" -gt 0 ]; then
    echo "#### Documentation-only files"
    echo
    echo "| Docs | File |"
    echo "| ---: | --- |"
    printf '%s' "$doc_rows" | sort -rn | awk -F'\t' 'NF == 2 { printf "| %s | `%s` |\n", $1, $2 }'
    echo
fi

# ------------------------------------------------------------ public API surface

echo "### Public API surface"
echo
if [ -z "$api_added" ] && [ -z "$api_removed" ]; then
    echo "No line carrying \`public\` or \`open\` was added or removed, across modified"
    echo "files and the full contents of any file added or deleted under \`Sources/\`."
    echo "Nothing a consumer compiles against moved, so this change is source compatible"
    echo "by that measure and needs no matching change in the SDK for Android."
else
    echo "Lines carrying \`public\` or \`open\` moved. The public surface is a contract"
    echo "shared with the SDK for Android, so a change here is a change to both."
    if [ -n "$api_removed" ]; then
        echo
        echo "Removed or altered:"
        echo '```'
        printf '%s' "$api_removed"
        echo '```'
    fi
    if [ -n "$api_added" ]; then
        echo
        echo "Added or altered:"
        echo '```'
        printf '%s' "$api_added"
        echo '```'
    fi
fi
echo

# ------------------------------------------------------------------ test balance

TEST_FILES=$(git diff --name-only "$BASE..$HEAD_SHA" -- Tests/ Example/PayabliDemo/FlowTests/ | grep -c . || true)
echo "### Tests"
echo
if [ "$semantic" -eq 0 ]; then
    echo "No production file changed a declaration or a statement, so no new test is implied."
elif [ "$TEST_FILES" -eq 0 ]; then
    echo "$semantic production files changed behaviour and no test file changed. Worth"
    echo "confirming the existing suite covers the new paths."
else
    echo "$semantic production files changed behaviour, alongside $TEST_FILES changed test files."
fi
