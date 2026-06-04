#!/usr/bin/env bash
#
# build_release_frameworks.sh
# ---------------------------
# Builds the Payabli iOS SDK distribution XCFrameworks
# (PayabliSDKCore, PayabliSDKTapToPay, PayabliSDKPayInPaymentFlow,
# PayabliCardReaderCore) for
# device + iOS Simulator slices, with distribution-mode settings and a
# pinned SOURCE_DATE_EPOCH for reproducible zips.
#
# PayInPaymentFlow is shipped as its own opt-in XCFramework. It is not part
# of the PayabliSDK umbrella product, but it is part of the public release
# payload below.
#
# Environment:
#   VERSION             required. Used as filename suffix.
#                       Example: 1.0.247-qa
#                       Passed via $GITHUB_ENV by the CI workflow.
#   SOURCE_DATE_EPOCH   optional. Defaults to the HEAD commit's timestamp so
#                       every re-build from the same commit produces a zip
#                       with the same sha256. Set explicitly in CI for
#                       extra confidence.
#   BUILD_CONFIG        optional. Defaults to `Release`.
#   DEVICE_DESTINATION  optional. Defaults to `generic/platform=iOS`.
#   SIM_DESTINATION     optional. Defaults to `generic/platform=iOS Simulator`.
#
# Outputs:
#   build/release/
#     payabli-ios-sdk-core-${VERSION}.zip
#     payabli-ios-sdk-taptopay-${VERSION}.zip
#     payabli-ios-sdk-payin-payment-flow-${VERSION}.zip
#     payabli-ios-sdk-card-reader-core-${VERSION}.zip
#     checksums.txt           (one sha256 per zip, space-separated lines)
#     THIRD_PARTY_LICENSES.txt  (bundled copy for the upload/publish step)
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

# Pin SOURCE_DATE_EPOCH to the HEAD commit's timestamp so every rebuild from
# the same commit produces a byte-identical zip (critical for SPM checksum
# stability). Overridable via environment.
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
    "PayabliCardReaderCore"
)

# Filename slug (without `payabli-ios-sdk-` prefix), mapped by scheme name.
slug_for() {
    case "$1" in
        PayabliSDKCore)          echo "core" ;;
        PayabliSDKTapToPay)      echo "taptopay" ;;
        PayabliSDKPayInPaymentFlow) echo "payin-payment-flow" ;;
        PayabliCardReaderCore)   echo "card-reader-core" ;;
        *) echo "error: unknown scheme '$1'" >&2; exit 1 ;;
    esac
}

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
    slug="$(slug_for "$scheme")"

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

    zip_name="payabli-ios-sdk-${slug}-${VERSION}.zip"
    zip_path="$BUILD_DIR/$zip_name"
    rm -f "$zip_path"
    echo "[release] zipping -> ${zip_name}"
    # ditto -c -k --keepParent is the Apple-sanctioned reproducible zip tool;
    # it respects SOURCE_DATE_EPOCH for entry mtimes on recent macOS.
    ( cd "$XCF_DIR" && ditto -c -k --keepParent "${scheme}.xcframework" "$zip_path" )
done

# sha256 checksums for Package.swift `binaryTarget`.
echo "[release] computing sha256 checksums"
checksums_file="$BUILD_DIR/checksums.txt"
: > "$checksums_file"
for scheme in "${SCHEMES[@]}"; do
    slug="$(slug_for "$scheme")"
    zip_name="payabli-ios-sdk-${slug}-${VERSION}.zip"
    checksum="$(swift package compute-checksum "$BUILD_DIR/$zip_name")"
    printf '%s  %s\n' "$checksum" "$zip_name" >> "$checksums_file"
    # Also expose individual vars for the render step:
    #   CORE_SHA256, TAPTOPAY_SHA256, PAYIN_PAYMENT_FLOW_SHA256,
    #   CARD_READER_CORE_SHA256
    # (matches render_public_manifests.sh's required vars).
    upper="$(echo "${slug//-/_}" | tr '[:lower:]' '[:upper:]')"
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        printf '%s_SHA256=%s\n' "$upper" "$checksum" >> "$GITHUB_ENV"
    fi
    printf '[release] %s -> %s\n' "$zip_name" "$checksum"
done

# Bundle the MIT attribution file alongside the zips so the upload step can
# ship it to S3 without reaching back into the repo.
cp "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$BUILD_DIR/THIRD_PARTY_LICENSES.txt"

echo "[release] done. Artifacts:"
find "$BUILD_DIR" -maxdepth 1 -type f | sort
cat "$checksums_file"
