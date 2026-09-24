#!/usr/bin/env bash
#
# build_release_frameworks.sh
# ---------------------------
# Builds one XCFramework per shipped module (PayabliSDKCore,
# PayabliSDKTapToPay, PayabliSDKPayInPaymentFlow, PayabliSDKTelemetry) for
# device + iOS Simulator slices, with distribution-mode settings, and packs
# them into one zip whose entry times are SOURCE_DATE_EPOCH. An integrator
# embeds Core and the modules they use, so an app that never takes a
# card-present payment never links the card reader.
#
# Environment:
#   VERSION             required. Used in the zip's filename.
#                       Example: 1.0.247-qa
#                       Passed via $GITHUB_ENV by the CI workflow.
#   SOURCE_DATE_EPOCH   optional. The zip's entry times. Defaults to the HEAD
#                       commit's timestamp.
#   BUILD_CONFIG        optional. Defaults to `Release`.
#   DEVICE_DESTINATION  optional. Defaults to `generic/platform=iOS`.
#   SIM_DESTINATION     optional. Defaults to `generic/platform=iOS Simulator`.
#
# Outputs:
#   build/release/
#     payabli-ios-sdk-${VERSION}.zip   PayabliSDK/ holding every XCFramework
#                                      and THIRD_PARTY_LICENSES.txt
#     checksums.txt                    the zip's sha256
#     THIRD_PARTY_LICENSES.txt         the attribution, beside the zip too
#
# Run locally:
#   VERSION=1.0.0-dev ./Scripts/build_release_frameworks.sh

set -euo pipefail

if [[ -z "${VERSION:-}" ]]; then
    echo "error: VERSION environment variable is required" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_CONFIG="${BUILD_CONFIG:-Release}"
DEVICE_DESTINATION="${DEVICE_DESTINATION:-generic/platform=iOS}"
SIM_DESTINATION="${SIM_DESTINATION:-generic/platform=iOS Simulator}"

# The zip's entry times, so zipping the same frameworks twice gives the same
# bytes. Overridable via environment.
if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
    SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
fi
export SOURCE_DATE_EPOCH

echo "[release] VERSION=${VERSION}"
echo "[release] BUILD_CONFIG=${BUILD_CONFIG}"
echo "[release] SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"

BUILD_DIR="$REPO_ROOT/build/release"
ARCHIVE_DIR="$BUILD_DIR/archives"
XCF_DIR="$BUILD_DIR/xcframeworks"
rm -rf "$BUILD_DIR"
mkdir -p "$ARCHIVE_DIR" "$XCF_DIR"

# Publicly shipped schemes. Each matches a Package.swift product.
SCHEMES=(
    "PayabliSDKCore"
    "PayabliSDKTapToPay"
    "PayabliSDKPayInPaymentFlow"
    "PayabliSDKTelemetry"
)

archive_scheme() {
    local scheme="$1" destination="$2" suffix="$3"
    local archive_path="$ARCHIVE_DIR/${scheme}-${suffix}.xcarchive"
    echo "[release] archiving ${scheme} (${suffix})"
    set +e
    if command -v xcpretty >/dev/null 2>&1; then
        xcodebuild archive \
            -scheme "$scheme" \
            -destination "$destination" \
            -archivePath "$archive_path" \
            -configuration "$BUILD_CONFIG" \
            SKIP_INSTALL=NO \
            BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            | xcpretty
        exit_code=${PIPESTATUS[0]}
    else
        xcodebuild archive \
            -scheme "$scheme" \
            -destination "$destination" \
            -archivePath "$archive_path" \
            -configuration "$BUILD_CONFIG" \
            SKIP_INSTALL=NO \
            BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO
        exit_code=$?
    fi
    set -e
    if [[ "$exit_code" -ne 0 ]]; then
        echo "error: xcodebuild archive failed (exit ${exit_code}) for ${scheme} (${suffix})" >&2
        exit "$exit_code"
    fi
    echo "$archive_path"
}

for scheme in "${SCHEMES[@]}"; do
    archive_scheme "$scheme" "$DEVICE_DESTINATION" "device" > /dev/null
    archive_scheme "$scheme" "$SIM_DESTINATION"   "sim"    > /dev/null

    device_framework="$ARCHIVE_DIR/${scheme}-device.xcarchive/Products/usr/local/lib/${scheme}.framework"
    sim_framework="$ARCHIVE_DIR/${scheme}-sim.xcarchive/Products/usr/local/lib/${scheme}.framework"

    if [[ ! -d "$device_framework" ]]; then
        echo "error: missing device slice for ${scheme} at ${device_framework}" >&2
        exit 1
    fi
    if [[ ! -d "$sim_framework" ]]; then
        echo "error: missing simulator slice for ${scheme} at ${sim_framework}" >&2
        exit 1
    fi

    xcf_output="$XCF_DIR/${scheme}.xcframework"
    rm -rf "$xcf_output"
    echo "[release] creating ${scheme}.xcframework"
    xcodebuild -create-xcframework \
        -framework "$device_framework" \
        -framework "$sim_framework" \
        -output "$xcf_output"
done

# One folder, one zip. Every scheme has exactly one XCFramework in it, so a
# build that lost a module fails here rather than shipping without it.
BUNDLE_DIR="$BUILD_DIR/PayabliSDK"
mkdir -p "$BUNDLE_DIR"
for scheme in "${SCHEMES[@]}"; do
    cp -R "$XCF_DIR/${scheme}.xcframework" "$BUNDLE_DIR/"
done
cp "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$BUNDLE_DIR/"
bundled="$(find "$BUNDLE_DIR" -maxdepth 1 -name '*.xcframework' | wc -l | tr -d ' ')"
if [[ "$bundled" -ne "${#SCHEMES[@]}" ]]; then
    echo "error: the bundle holds ${bundled} XCFrameworks for ${#SCHEMES[@]} schemes" >&2
    exit 1
fi

zip_name="payabli-ios-sdk-${VERSION}.zip"
zip_path="$BUILD_DIR/$zip_name"
rm -f "$zip_path"
echo "[release] zipping -> ${zip_name}"
# ditto stores each file's modification time, and a copy is stamped with the
# time it was made, so every entry is set to SOURCE_DATE_EPOCH first.
find "$BUNDLE_DIR" -exec touch -h -t "$(date -r "$SOURCE_DATE_EPOCH" +%Y%m%d%H%M.%S)" {} +
( cd "$BUILD_DIR" && ditto -c -k --keepParent "PayabliSDK" "$zip_path" )

checksums_file="$BUILD_DIR/checksums.txt"
( cd "$BUILD_DIR" && shasum -a 256 "$zip_name" > "$checksums_file" )
cp "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$BUILD_DIR/THIRD_PARTY_LICENSES.txt"

echo "[release] done. Artifacts:"
find "$BUILD_DIR" -maxdepth 1 -type f | sort
cat "$checksums_file"
