#!/usr/bin/env bash
#
# refresh_vendored_ttp.sh
# -----------------------
# Re-vendor the MIT-licensed `FiservTTP` source into
# `ThirdParty/PayabliCardReaderCoreSource/` when Fiserv publishes a new
# upstream tag.
#
# Usage:
#   ./Scripts/refresh_vendored_ttp.sh <upstream-tag>
#
# Examples:
#   ./Scripts/refresh_vendored_ttp.sh 1.0.8
#   ./Scripts/refresh_vendored_ttp.sh main          # latest trunk
#
# What this script does:
#   1. Temporarily adds `Fiserv/TTPPackage` as an SPM dep at the requested tag
#      (by writing a throwaway `.swiftpm/refresh-vendor.swift` manifest in a
#      scratch dir so the checked-in Package.swift isn't touched).
#   2. Runs `swift package resolve` to fetch the upstream checkout.
#   3. `rsync`s the 5 .swift source files into
#      ThirdParty/PayabliCardReaderCoreSource/Sources/PayabliCardReaderCore/.
#   4. Updates the "Upstream version pinned" block in the vendor README.
#   5. Runs `swift build` to verify the refreshed source still compiles.
#
# Post-run manual steps:
#   - Review the diff inside ThirdParty/PayabliCardReaderCoreSource/ carefully.
#     In particular, re-check any removed or renamed public API against the
#     FiservCardReader adapter — upstream breaking changes ARE possible.
#   - Update the CHANGELOG (if applicable) and commit with
#     `chore(vendor): refresh PayabliCardReaderCore from Fiserv/TTPPackage <tag>`.
#   - Cut a patch SDK release if the upstream changes are substantive
#     (security fixes, new transaction types, etc.).

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <upstream-tag>" >&2
    echo "Example: $0 1.0.8" >&2
    exit 2
fi

UPSTREAM_TAG="$1"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$REPO_ROOT/ThirdParty/PayabliCardReaderCoreSource/Sources/PayabliCardReaderCore"
VENDOR_README="$REPO_ROOT/ThirdParty/PayabliCardReaderCoreSource/README.md"

if [[ ! -d "$VENDOR_DIR" ]]; then
    echo "error: expected $VENDOR_DIR to exist" >&2
    exit 1
fi

# Scratch directory holding a throwaway SPM manifest that pulls the requested
# upstream tag. Using a scratch dir keeps the repo-level Package.swift clean.
SCRATCH_DIR="$(mktemp -d -t payabli-ttp-refresh-XXXXXX)"
trap 'rm -rf "$SCRATCH_DIR"' EXIT

cat > "$SCRATCH_DIR/Package.swift" <<SWIFT_EOF
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RefreshVendoredTTP",
    platforms: [.iOS("16.7"), .macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/Fiserv/TTPPackage.git", exact: "$UPSTREAM_TAG")
    ],
    targets: [
        .target(name: "RefreshVendoredTTP", path: "Source")
    ]
)
SWIFT_EOF

mkdir -p "$SCRATCH_DIR/Source"
cat > "$SCRATCH_DIR/Source/Placeholder.swift" <<'SWIFT_EOF'
public enum Placeholder {}
SWIFT_EOF

echo "[refresh] resolving upstream Fiserv/TTPPackage@$UPSTREAM_TAG in $SCRATCH_DIR"
(
    cd "$SCRATCH_DIR"
    swift package resolve
)

UPSTREAM_SOURCE="$SCRATCH_DIR/.build/checkouts/TTPPackage/Sources/FiservTTP"
if [[ ! -d "$UPSTREAM_SOURCE" ]]; then
    echo "error: upstream checkout not found at $UPSTREAM_SOURCE" >&2
    exit 1
fi

UPSTREAM_SHA="$(cd "$SCRATCH_DIR/.build/checkouts/TTPPackage" && git rev-parse --short HEAD)"
echo "[refresh] upstream commit: $UPSTREAM_SHA ($UPSTREAM_TAG)"

# rsync only the 5 .swift files we vendor (skip the umbrella header by design).
SWIFT_SOURCES=(
    "FiservPaymentModels.swift"
    "FiservTTPCardReader.swift"
    "FiservTTPModels.swift"
    "FiservTTPReader.swift"
    "FiservTTPServices.swift"
)

echo "[refresh] copying ${#SWIFT_SOURCES[@]} source files into $VENDOR_DIR"
for f in "${SWIFT_SOURCES[@]}"; do
    src="$UPSTREAM_SOURCE/$f"
    if [[ ! -f "$src" ]]; then
        echo "error: upstream file missing: $src" >&2
        exit 1
    fi
    cp "$src" "$VENDOR_DIR/$f"
    chmod u+w "$VENDOR_DIR/$f"
done

# Surface any new .swift files that upstream added so a human can decide
# whether to adopt them.
NEW_FILES=()
while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    match=0
    for expected in "${SWIFT_SOURCES[@]}"; do
        if [[ "$base" == "$expected" ]]; then
            match=1
            break
        fi
    done
    if [[ $match -eq 0 && "$base" == *.swift ]]; then
        NEW_FILES+=("$base")
    fi
done < <(find "$UPSTREAM_SOURCE" -maxdepth 1 -type f -name '*.swift' -print0)

if [[ ${#NEW_FILES[@]} -gt 0 ]]; then
    echo "[refresh] WARNING: upstream has new .swift files not in the vendored set:"
    for f in "${NEW_FILES[@]}"; do
        echo "    $f"
    done
    echo "[refresh] review and update the SWIFT_SOURCES array in this script if you want to adopt them."
fi

# Update the "Upstream version pinned" block in the vendor README using a
# portable awk rewrite (no GNU-specific sed flags).
TMP_README="$(mktemp)"
awk -v tag="$UPSTREAM_TAG" -v sha="$UPSTREAM_SHA" '
  BEGIN { in_table = 0 }
  /^## Upstream version pinned/ { in_table = 1; print; next }
  in_table && /^\| Commit \|/ { print "| Commit | `" sha "` |"; next }
  in_table && /^\| Tag \|/    { print "| Tag | `" tag "` |"; next }
  in_table && /^## / && !/^## Upstream version pinned/ { in_table = 0 }
  { print }
' "$VENDOR_README" > "$TMP_README"
mv "$TMP_README" "$VENDOR_README"

echo "[refresh] running swift build to verify refreshed source"
(
    cd "$REPO_ROOT"
    swift build
)

echo "[refresh] done. Review the diff and commit:"
echo "    git diff ThirdParty/PayabliCardReaderCoreSource/"
echo "    git commit -am 'chore(vendor): refresh PayabliCardReaderCore from Fiserv/TTPPackage $UPSTREAM_TAG'"
