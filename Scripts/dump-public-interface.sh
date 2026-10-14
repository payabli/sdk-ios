#!/usr/bin/env bash
#
# dump-public-interface.sh
# ------------------------
# Writes the Swift interface of every module the release ships, one file per
# module, so a change to what an integrator can reach shows up as a diff.
#
# The file is the module's `.private.swiftinterface`: the public interface plus
# any `@_spi` declaration, which an integrator can still import. The package
# interface is left out, because nothing outside this package can reach it.
#
# The header keeps the format version and the module flags. The compiler
# version lines are dropped, and `-package-name` is rewritten to a fixed value,
# because SwiftPM derives it from the checkout directory's name.
#
# Usage:
#   ./Scripts/dump-public-interface.sh API
#   ./Scripts/dump-public-interface.sh --products <products-dir> [--triple <triple>] <out-dir>
#
# With `--products`, nothing is built: the interfaces are read from a build
# that already ran, which is how the release reads its own. `--triple` picks
# the slice, and defaults to the device one, `arm64-apple-ios`.
#
# Environment:
#   BUILD_CONFIG   optional. Defaults to `Release`.
#   DERIVED_DATA   optional. Defaults to build/public-interface/derived.

set -euo pipefail

USAGE="usage: $0 [--products <products-dir>] [--triple <triple>] <output-directory>"
PRODUCTS=""
TRIPLE="arm64-apple-ios"
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --products) PRODUCTS="${2:?$USAGE}" ;;
        --triple) TRIPLE="${2:?$USAGE}" ;;
        *) echo "$USAGE" >&2; exit 1 ;;
    esac
    shift 2
done
OUT_DIR="${1:?$USAGE}"

# Relative paths are the caller's, so they are resolved before the cd below.
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
if [[ -n "$PRODUCTS" ]]; then
    if [[ ! -d "$PRODUCTS" ]]; then
        echo "error: no products directory at ${PRODUCTS}" >&2
        exit 1
    fi
    PRODUCTS="$(cd "$PRODUCTS" && pwd)"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# The record holds only the committed environments. A file adding one is
# gitignored, so nothing in the tracked tree shows it is here.
extras="$(find Sources -name 'PayabliEnvironment+Extras.swift' -print -quit)"
if [[ -n "$extras" ]]; then
    echo "error: ${extras} adds environments the recorded interface must not carry; remove it and run again" >&2
    exit 1
fi

BUILD_CONFIG="${BUILD_CONFIG:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/build/public-interface/derived}"

# The modules the release zip ships, as `build_release_frameworks.sh` lists them.
MODULES=(
    "PayabliSDKCore"
    "PayabliSDKTelemetry"
    "PayabliSDKTapToPay"
    "PayabliSDKPayIn"
)

if [[ -z "$PRODUCTS" ]]; then
    args=(
        build
        -scheme PayabliSDK-Package
        -destination "generic/platform=iOS"
        -configuration "$BUILD_CONFIG"
        -derivedDataPath "$DERIVED_DATA"
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES
        CODE_SIGNING_ALLOWED=NO
    )
    set +e
    if command -v xcpretty >/dev/null 2>&1; then
        xcodebuild "${args[@]}" | xcpretty >&2
        exit_code=${PIPESTATUS[0]}
    else
        xcodebuild "${args[@]}" >&2
        exit_code=$?
    fi
    set -e
    if [[ "$exit_code" -ne 0 ]]; then
        echo "error: xcodebuild failed (exit ${exit_code})" >&2
        exit "$exit_code"
    fi
    PRODUCTS="$DERIVED_DATA/Build/Products/${BUILD_CONFIG}-iphoneos"
fi

for module in "${MODULES[@]}"; do
    # A package build leaves the module beside its framework, and a framework
    # build can leave it inside, so both are searched and exactly one must exist.
    found="$(find "$PRODUCTS" -path "*/$module.swiftmodule/$TRIPLE.private.swiftinterface")"
    count="$(grep -c . <<<"$found" || true)"
    if [[ "$count" -ne 1 ]] || [[ ! -s "$found" ]]; then
        echo "error: expected one ${TRIPLE} interface for ${module} under ${PRODUCTS}, found ${count}" >&2
        exit 1
    fi
    grep -vE '^// swift-(compiler-version|module-flags-ignorable):' "$found" \
        | sed -E '/^\/\/ swift-module-flags:/s/-package-name [^ ]+/-package-name PayabliSDK/' \
        > "$OUT_DIR/$module.swiftinterface"
done
