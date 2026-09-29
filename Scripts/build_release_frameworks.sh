#!/usr/bin/env bash
#
# build_release_frameworks.sh
# ---------------------------
# Builds one XCFramework per shipped module (PayabliSDKCore,
# PayabliSDKTelemetry, PayabliSDKTapToPay, PayabliSDKPayIn) for
# device + iOS Simulator slices, with distribution-mode settings, and packs
# them into one zip whose entry times are SOURCE_DATE_EPOCH. An integrator
# embeds TapToPay, PayIn or both, and always Core and Telemetry,
# which both capabilities load. An app that never takes a card-present
# payment never links the card reader.
#
# Core and Telemetry are shared targets, not products, so no scheme builds
# them alone. A generated client package links both capability products, and
# that is what makes Xcode build each shared target once, as its own
# framework, with the capabilities loading it rather than carrying a copy.
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
CLIENT_DIR="$BUILD_DIR/client"
STAGE_DIR="$BUILD_DIR/stage"
XCF_DIR="$BUILD_DIR/xcframeworks"
rm -rf "$BUILD_DIR"
mkdir -p "$CLIENT_DIR/Sources/PayabliReleaseClient" "$STAGE_DIR" "$XCF_DIR"

# Every module the zip ships. Core first: the others load it.
MODULES=(
    "PayabliSDKCore"
    "PayabliSDKTelemetry"
    "PayabliSDKTapToPay"
    "PayabliSDKPayIn"
)
# The two that link Core and Telemetry rather than carrying them.
CAPABILITIES=(
    "PayabliSDKTapToPay"
    "PayabliSDKPayIn"
)

# The resource bundle each framework carries, where its generated `.module`
# accessor looks for it. TapToPay carries the card reader's, which it links.
bundle_for() {
    case "$1" in
        PayabliSDKCore) echo "PayabliSDK_PayabliSDKCore.bundle" ;;
        PayabliSDKTapToPay) echo "PayabliSDK_PayabliCardReaderCore.bundle" ;;
        PayabliSDKPayIn) echo "PayabliSDK_PayabliSDKPayIn.bundle" ;;
        *) echo "" ;;
    esac
}

# A path dependency's identity is its directory's name, lowercased, less a `.git` suffix.
package_identity="$(basename "$REPO_ROOT" | tr '[:upper:]' '[:lower:]' | sed 's/\.git$//')"
cat > "$CLIENT_DIR/Package.swift" <<EOF
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PayabliReleaseClient",
    platforms: [.iOS("16.7")],
    products: [
        .library(name: "PayabliReleaseClient", type: .dynamic, targets: ["PayabliReleaseClient"])
    ],
    dependencies: [.package(path: "$REPO_ROOT")],
    targets: [
        .target(name: "PayabliReleaseClient", dependencies: [
            .product(name: "PayabliSDKTapToPay", package: "$package_identity"),
            .product(name: "PayabliSDKPayIn", package: "$package_identity")
        ])
    ]
)
EOF
printf 'import PayabliSDKTapToPay\nimport PayabliSDKPayIn\n' \
    > "$CLIENT_DIR/Sources/PayabliReleaseClient/Client.swift"

# Prints the products directory the build wrote.
build_client() {
    local destination="$1" suffix="$2"
    local derived="$BUILD_DIR/derived-${suffix}"
    echo "[release] building (${suffix})" >&2
    local args=(
        build
        -scheme PayabliReleaseClient
        -destination "$destination"
        -configuration "$BUILD_CONFIG"
        -derivedDataPath "$derived"
        SKIP_INSTALL=NO
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=NO
    )
    # Runs in the caller's command substitution, so this cd stays here.
    cd "$CLIENT_DIR"
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
        echo "error: xcodebuild failed (exit ${exit_code}) for the release client (${suffix})" >&2
        exit "$exit_code"
    fi
    find "$derived/Build/Products" -maxdepth 1 -type d -name "${BUILD_CONFIG}-*" | head -1
}

# Copies one module's framework out of a build, with the interface and the
# resources an integrator needs, and prints where it put it.
stage_framework() {
    local products="$1" module="$2" suffix="$3"
    local framework="$STAGE_DIR/$suffix/$module.framework"
    mkdir -p "$STAGE_DIR/$suffix"
    cp -R "$products/PackageFrameworks/$module.framework" "$framework"
    if [[ ! -d "$framework/Modules/$module.swiftmodule" ]]; then
        mkdir -p "$framework/Modules"
        cp -R "$products/$module.swiftmodule" "$framework/Modules/"
    fi
    # The private and package interfaces declare what is not public.
    find "$framework/Modules" \
        \( -name '*.private.swiftinterface' -o -name '*.package.swiftinterface' \) -delete
    local bundle
    bundle="$(bundle_for "$module")"
    if [[ -n "$bundle" ]]; then
        cp -R "$products/$bundle" "$framework/"
        if [[ -f "$products/$bundle/PrivacyInfo.xcprivacy" ]]; then
            cp "$products/$bundle/PrivacyInfo.xcprivacy" "$framework/"
        fi
    fi
    echo "$framework"
}

# Refuses a framework an integrator could not import or run: no public
# interface, a non-public one, a missing resource bundle, a load of a Payabli
# framework the zip does not ship, or a capability that carries its own copy
# of a shared module instead of loading it.
check_framework() {
    local framework="$1" module="$2"
    local interfaces
    interfaces="$(find "$framework/Modules/$module.swiftmodule" -name '*.swiftinterface' | wc -l | tr -d ' ')"
    if [[ "$interfaces" -eq 0 ]]; then
        echo "error: ${framework} has no module interface" >&2
        exit 1
    fi
    if find "$framework/Modules" -name '*.private.swiftinterface' -o -name '*.package.swiftinterface' | grep -q .; then
        echo "error: ${framework} ships a non-public interface" >&2
        exit 1
    fi
    local bundle
    bundle="$(bundle_for "$module")"
    if [[ -n "$bundle" ]] && [[ -z "$(ls -A "$framework/$bundle" 2>/dev/null)" ]]; then
        echo "error: ${framework} has no ${bundle}" >&2
        exit 1
    fi
    local loaded
    for loaded in $(otool -L "$framework/$module" | awk '/@rpath\/Payabli[A-Za-z]*\.framework/ { print $1 }'); do
        loaded="$(basename "$loaded")"
        [[ "$loaded" == "$module" ]] && continue
        if [[ " ${MODULES[*]} " != *" ${loaded} "* ]]; then
            echo "error: ${framework} loads ${loaded}, which the zip does not ship" >&2
            exit 1
        fi
    done
    local capability shared
    for capability in "${CAPABILITIES[@]}"; do
        [[ "$module" == "$capability" ]] || continue
        for shared in PayabliSDKCore PayabliSDKTelemetry; do
            if ! otool -L "$framework/$module" | grep -q "@rpath/${shared}.framework/${shared}"; then
                echo "error: ${framework} does not load ${shared}" >&2
                exit 1
            fi
        done
    done
}

device_products="$(build_client "$DEVICE_DESTINATION" "device")"
sim_products="$(build_client "$SIM_DESTINATION" "sim")"

for module in "${MODULES[@]}"; do
    device_framework="$(stage_framework "$device_products" "$module" "device")"
    sim_framework="$(stage_framework "$sim_products" "$module" "sim")"
    check_framework "$device_framework" "$module"
    check_framework "$sim_framework" "$module"

    xcf_output="$XCF_DIR/${module}.xcframework"
    echo "[release] creating ${module}.xcframework"
    xcodebuild -create-xcframework \
        -framework "$device_framework" \
        -framework "$sim_framework" \
        -output "$xcf_output"
    for slice_framework in "$xcf_output"/*/"$module.framework"; do
        check_framework "$slice_framework" "$module"
    done
done

# One folder, one zip. Every module has exactly one XCFramework in it, so a
# build that lost a module fails here rather than shipping without it.
BUNDLE_DIR="$BUILD_DIR/PayabliSDK"
mkdir -p "$BUNDLE_DIR"
for module in "${MODULES[@]}"; do
    cp -R "$XCF_DIR/${module}.xcframework" "$BUNDLE_DIR/"
done
cp "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$BUNDLE_DIR/"
bundled="$(find "$BUNDLE_DIR" -maxdepth 1 -name '*.xcframework' | wc -l | tr -d ' ')"
if [[ "$bundled" -ne "${#MODULES[@]}" ]]; then
    echo "error: the bundle holds ${bundled} XCFrameworks for ${#MODULES[@]} modules" >&2
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
