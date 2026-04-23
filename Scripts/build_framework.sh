#!/bin/bash
# Builds a universal XCFramework containing PayabliSDKCore + PayabliSDKPayIn.
# Outputs: build/PayabliSDK.xcframework

set -euo pipefail

SCHEME="PayabliSDK"
FRAMEWORK_NAME="PayabliSDK"
BUILD_DIR="build"
ARCHIVE_DIR="${BUILD_DIR}/archives"

rm -rf "${BUILD_DIR}"
mkdir -p "${ARCHIVE_DIR}"

echo "==> Archiving for iOS device (arm64)..."
xcodebuild archive \
    -scheme "${SCHEME}" \
    -destination "generic/platform=iOS" \
    -archivePath "${ARCHIVE_DIR}/ios_device.xcarchive" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO \
    ONLY_ACTIVE_ARCH=NO \
    | xcpretty

echo "==> Archiving for iOS simulator (arm64 + x86_64)..."
xcodebuild archive \
    -scheme "${SCHEME}" \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "${ARCHIVE_DIR}/ios_simulator.xcarchive" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO \
    ONLY_ACTIVE_ARCH=NO \
    | xcpretty

echo "==> Creating XCFramework..."
xcodebuild -create-xcframework \
    -framework "${ARCHIVE_DIR}/ios_device.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
    -framework "${ARCHIVE_DIR}/ios_simulator.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
    -output "${BUILD_DIR}/${FRAMEWORK_NAME}.xcframework"

echo "==> Done. Framework at: ${BUILD_DIR}/${FRAMEWORK_NAME}.xcframework"
