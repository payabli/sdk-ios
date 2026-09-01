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

# The long lists below fold away, so the report reads as a summary and a reviewer
# opens only the part they are acting on. GitHub needs a blank line after
# </summary>, or the Markdown inside renders as literal text, and one before
# </details>, or a trailing table swallows the tag. Each summary carries its own
# count, since that line is what gets read while the block is shut.
noun() { if [ "$1" -eq 1 ]; then printf '%s' "$2"; else printf '%ss' "$2"; fi; }

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
    # git reports a regular file that became a symlink as `T`, which none of the
    # three counts covers. The list is folded away, so a summary that did not add
    # up to it would hide that file behind three zeroes.
    listed=$(printf '%s\n' "$LIFECYCLE" | grep -c . || true)
    other=$((listed - added - deleted - renamed))
    summary="$added added, $deleted deleted, $renamed renamed"
    if [ "$other" -gt 0 ]; then
        summary="$summary, $other other"
    fi
    echo "<details>"
    echo "<summary>$summary</summary>"
    echo
    echo '```'
    printf '%s\n' "$LIFECYCLE"
    echo '```'
    if printf '%s\n' "$LIFECYCLE" | grep -qE '^R0[0-9][0-9]' ; then
        echo
        echo "A rename shown below \`R100\` was edited as well as moved."
    fi
    echo
    echo "</details>"
fi
echo

# ------------------------------------------------------------------ shipped code

# Swift only. Sources/ also carries Markdown, and prose about a public type
# reads as a declaration to a grep.
#
# A modified file and a renamed one both carry an edit, and git reports the
# rename as `R` rather than `M`. Reading only `M` skips a file that was renamed
# and edited in the same commit, which is the case most in need of review. Each
# is therefore held as an old path at the base and a new path at the head; for a
# modified file the two are the same.
SOURCE_PAIRS=$(git diff --name-status --find-renames "$BASE..$HEAD_SHA" -- Sources/ \
    | awk -F'\t' '
        $1 ~ /^M/ && $2 ~ /\.swift$/ { print $2 "\t" $2 }
        $1 ~ /^R/ && $3 ~ /\.swift$/ { print $2 "\t" $3 }
    ' || true)
CHANGED_SOURCES=$(printf '%s\n' "$SOURCE_PAIRS" | awk -F'\t' 'NF == 2 { print $2 }' | grep . || true)
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

# Every declaration in a file that a consumer can see, one per line.
#
# Searching changed lines for the word `public` finds a minority of the surface.
# An enum's cases carry the enum's visibility and name it nowhere, so all of
# `PayabliTTPEvent` is invisible to that search; so is `activateDevice`, a member
# of a `public extension` that needs no keyword of its own. Swift's default
# differs by container, so the container is what gets tracked:
#
#   public extension, public protocol   a member is public
#   public enum                         a `case` is public, a `func` is internal
#   public struct, class, actor         a member is internal
#
# An explicit `private`, `fileprivate` or `internal` always wins.
#
# A text scan, not a compiler: it does not resolve conditional compilation, and
# a declaration split across lines is read by its first line. It is enough to
# say which declarations to look at, which is what the section it feeds claims.
public_surface() {
    awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    # Braces inside a string literal are text, not scope. Counting them shifts
    # the depth for the rest of the file and every later visibility with it.
    function scan(s,   i, c, inq, esc) {
        opens = 0; closes = 0; inq = 0; esc = 0
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (esc) { esc = 0; continue }
            if (c == "\\") { esc = 1; continue }
            if (c == "\"") { inq = !inq; continue }
            if (inq) continue
            if (c == "{") opens++
            if (c == "}") closes++
        }
    }
    BEGIN { depth = 0; memberpub[0] = 0; casepub[0] = 0 }
    {
        line = $0
        if (inblock) {
            if (line ~ /\*\//) { sub(/^.*\*\//, "", line); inblock = 0 } else { next }
        }
        gsub(/\/\*[^*]*\*\//, "", line)
        if (line ~ /\/\*/) { sub(/\/\*.*$/, "", line); inblock = 1 }
        sub(/\/\/.*$/, "", line)
        t = trim(line)
        if (t == "") next

        lowered = (t ~ /(^|[[:space:]])(private|fileprivate|internal)([[:space:](]|$)/)
        raised  = (t ~ /(^|[[:space:]])(public|open)([[:space:]]|$)/)
        is_case = (t ~ /^case[[:space:]]/)
        is_decl = (t ~ /(^|[[:space:]])(func|var|let|init|subscript|typealias|associatedtype|class|struct|enum|protocol|extension|actor)([[:space:]<(:]|$)/)

        visible = 0
        if (raised && !lowered) visible = 1
        else if (!lowered) {
            if (is_case && casepub[depth]) visible = 1
            else if (is_decl && memberpub[depth]) visible = 1
        }

        if (visible && (is_decl || is_case)) print t

        scan(line)
        if (opens > 0) {
            newmember = 0; newcase = 0
            if (visible) {
                if (t ~ /(^|[[:space:]])(extension|protocol)([[:space:]]|$)/) newmember = 1
                else if (t ~ /(^|[[:space:]])enum([[:space:]]|$)/) newcase = 1
            }
            for (i = 0; i < opens; i++) {
                depth++
                memberpub[depth] = newmember
                casepub[depth] = newcase
            }
        }
        for (i = 0; i < closes; i++) if (depth > 0) depth--
    }
    ' "$1"
}

inert=0            # files whose entire diff the formatter would have produced
doc_only=0         # files whose remaining diff is comments and blank lines
semantic=0         # files with a changed declaration or statement
rows=""            # per-file detail for the files that carry a semantic change
doc_rows=""
api_added=""
api_removed=""

while IFS=$'\t' read -r old_path path; do
    [ -n "$path" ] || continue
    mkdir -p "$WORK/$(dirname "$old_path")"
    git show "$BASE:$old_path" > "$WORK/$old_path" 2>/dev/null || continue
    # Normalising the base revision is what separates the author's edit from the
    # formatter's. Without it every reformatted file looks like a rewrite.
    swiftformat "$WORK/$old_path" --config "$REPO_ROOT/.swiftformat" --quiet >/dev/null 2>&1
    git show "$HEAD_SHA:$path" > "$WORK/head-version" 2>/dev/null || continue

    if cmp -s "$WORK/$old_path" "$WORK/head-version"; then
        inert=$((inert + 1))
        continue
    fi

    changed=$(diff "$WORK/$old_path" "$WORK/head-version" | grep -E '^[<>]' || true)

    # Both sides of the diff, counted. An earlier version netted out a line that
    # was removed from one place and added unchanged in another, on the grounds
    # that a move compiles to what it compiled to before. That is not true of a
    # statement: order is behaviour, so validation moved to after the network
    # call it guards is a change made entirely of unaltered lines, and netting
    # reported it as nothing to read.
    side() {   # $1 = < or >, $2 = keep|drop comments
        local filter='^(///|//|/\*|\*/|\*)'
        printf '%s\n' "$changed" | grep -E "^$1" | sed -E 's/^.[[:space:]]*//' \
            | if [ "$2" = drop ]; then grep -vE "$filter"; else grep -E "$filter"; fi \
            | grep -v '^[[:space:]]*$' | sed -E 's/[[:space:]]+/ /g' | sort
    }
    code=$(( $(side '<' drop | grep -c . || true) + $(side '>' drop | grep -c . || true) ))
    comments=$(( $(side '<' keep | grep -c . || true) + $(side '>' keep | grep -c . || true) ))

    # The contract consumers compile against, which the repository holds in
    # common with the SDK for Android. Both sides are the whole visible surface
    # of the file, so a declaration that moved within it is not reported as a
    # change, and one that changed shape is reported from both ends.
    public_surface "$WORK/$old_path" | sort > "$WORK/api-base"
    public_surface "$WORK/head-version" | sort > "$WORK/api-head"
    added_api=$(comm -13 "$WORK/api-base" "$WORK/api-head")
    removed_api=$(comm -23 "$WORK/api-base" "$WORK/api-head")
    [ -n "$added_api" ] && api_added="${api_added}${path}"$'\n'"${added_api}"$'\n'
    [ -n "$removed_api" ] && api_removed="${api_removed}${path}"$'\n'"${removed_api}"$'\n'

    if [ "$code" -gt 0 ]; then
        semantic=$((semantic + 1))
        rows="${rows}${code}	${comments}	${path}"$'\n'
    else
        doc_only=$((doc_only + 1))
        doc_rows="${doc_rows}${comments}	${path}"$'\n'
    fi
done <<< "$SOURCE_PAIRS"

# A file that entered or left the build carries its whole contents as added or
# removed API. The classification above speaks only for modified files, so
# without this the report would call a new public type source compatible.
while IFS= read -r path; do
    [ -n "$path" ] || continue
    git show "$HEAD_SHA:$path" > "$WORK/lifecycle-version" 2>/dev/null || continue
    decls=$(public_surface "$WORK/lifecycle-version")
    [ -n "$decls" ] && api_added="${api_added}${path} (file added)"$'\n'"${decls}"$'\n'
done <<< "$ADDED_SOURCES"

while IFS= read -r path; do
    [ -n "$path" ] || continue
    git show "$BASE:$path" > "$WORK/lifecycle-version" 2>/dev/null || continue
    decls=$(public_surface "$WORK/lifecycle-version")
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
    echo "<details>"
    echo "<summary>$semantic $(noun "$semantic" file) that can change behaviour</summary>"
    echo
    echo "\`Code\` counts declarations and executable statements that differ once"
    echo "formatting is normalised, on both sides of the diff, so an altered line"
    echo "counts twice and a line that only moved still counts. Order is behaviour:"
    echo "validation moved to after the network call it guards is a change made"
    echo "entirely of unaltered lines. \`Docs\` is the same count for comments."
    echo
    echo "| Code | Docs | File |"
    echo "| ---: | ---: | --- |"
    printf '%s' "$rows" | sort -rn | awk -F'\t' 'NF == 3 { printf "| %s | %s | `%s` |\n", $1, $2, $3 }'
    echo
    echo "</details>"
    echo
fi

if [ "$doc_only" -gt 0 ]; then
    echo "<details>"
    echo "<summary>$doc_only $(noun "$doc_only" 'documentation-only file')</summary>"
    echo
    echo "| Docs | File |"
    echo "| ---: | --- |"
    printf '%s' "$doc_rows" | sort -rn | awk -F'\t' 'NF == 2 { printf "| %s | `%s` |\n", $1, $2 }'
    echo
    echo "</details>"
    echo
fi

# ------------------------------------------------------------ public API surface

echo "### Public API surface"
echo
if [ -z "$api_added" ] && [ -z "$api_removed" ]; then
    echo "No declaration a consumer can see was added or removed, across modified,"
    echo "renamed, added and deleted files under \`Sources/\`. This counts a member of a"
    echo "\`public extension\` and an enum's cases, neither of which carries the keyword."
    echo "It is a text scan rather than a compiled comparison, so read it as nothing"
    echo "found to look at, not as a source-compatibility guarantee."
else
    echo "Declarations a consumer can see were added or removed. The public surface is a"
    echo "contract shared with the SDK for Android, so a change here is a change to both."
    # A path is a heading in these listings, not a declaration, so it is not
    # counted as one.
    api_count() { printf '%s' "$1" | grep -vcE '\.swift( \(file (added|deleted)\))?$' || true; }
    if [ -n "$api_removed" ]; then
        n=$(api_count "$api_removed")
        echo
        echo "<details>"
        echo "<summary>Removed or altered: $n $(noun "$n" declaration)</summary>"
        echo
        echo '```'
        printf '%s' "$api_removed"
        echo '```'
        echo
        echo "</details>"
    fi
    if [ -n "$api_added" ]; then
        n=$(api_count "$api_added")
        echo
        echo "<details>"
        echo "<summary>Added or altered: $n $(noun "$n" declaration)</summary>"
        echo
        echo '```'
        printf '%s' "$api_added"
        echo '```'
        echo
        echo "</details>"
    fi
fi
echo

# ------------------------------------------------------------------ test balance

TEST_FILES=$(git diff --name-only "$BASE..$HEAD_SHA" -- Tests/ Example/PayabliDemo/FlowTests/ | grep -c . || true)
echo "### Tests"
echo
# An added or deleted production file is a behaviour change with no counterpart
# in `semantic`, which counts edits to files that existed on both sides. Reading
# `semantic` alone lets a change that adds a whole implementation with no test
# report that no test is implied.
production_changed=$((semantic + added_total + deleted_total))
if [ "$production_changed" -eq 0 ]; then
    echo "No production file changed a declaration or a statement, so no new test is implied."
elif [ "$TEST_FILES" -eq 0 ]; then
    echo "$production_changed production files changed behaviour and no test file changed. Worth"
    echo "confirming the existing suite covers the new paths."
else
    echo "$production_changed production files changed behaviour, alongside $TEST_FILES changed test files."
fi
