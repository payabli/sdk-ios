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
#   ./Scripts/dump-public-interface.sh --products <device-products-dir> <out-dir>
#
# With `--products`, nothing is built: the interfaces are read from a build
# that already ran, which is how the release reads its own.
#
# Environment:
#   BUILD_CONFIG   optional. Defaults to `Release`.
#   DERIVED_DATA   optional. Defaults to build/public-interface/derived.

set -euo pipefail

PRODUCTS=""
if [[ "${1:-}" == "--products" ]]; then
    PRODUCTS="${2:?usage: $0 --products <device-products-dir> <output-directory>}"
    shift 2
fi
OUT_DIR="${1:?usage: $0 [--products <device-products-dir>] <output-directory>}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

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

if [[ ! -d "$PRODUCTS" ]]; then
    echo "error: no products directory at ${PRODUCTS}" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
for module in "${MODULES[@]}"; do
    # A package build leaves the module beside its framework, and a framework
    # build can leave it inside, so both are searched and exactly one must exist.
    found="$(find "$PRODUCTS" -path "*/$module.swiftmodule/arm64-apple-ios.private.swiftinterface")"
    count="$(grep -c . <<<"$found" || true)"
    if [[ "$count" -ne 1 ]] || [[ ! -s "$found" ]]; then
        echo "error: expected one interface for ${module} under ${PRODUCTS}, found ${count}" >&2
        exit 1
    fi
    grep -vE '^// swift-(compiler-version|module-flags-ignorable):' "$found" \
        | sed -E '/^\/\/ swift-module-flags:/s/-package-name [^ ]+/-package-name PayabliSDK/' \
        > "$OUT_DIR/$module.swiftinterface"
done
