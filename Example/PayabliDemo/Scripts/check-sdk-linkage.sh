#!/bin/bash
#
# Reports how this build reaches the Payabli SDK, and stops the build rather than
# guessing when the answer is not deliverable.
#
# Driven by PAYABLI_SDK_LINKAGE from the active build configuration
# (Config/*.xcconfig). Run as a pre-build phase on the PayabliDemo target.
set -euo pipefail

LINKAGE="${PAYABLI_SDK_LINKAGE:-}"

if [[ -z "$LINKAGE" ]]; then
    echo "warning: PAYABLI_SDK_LINKAGE is unset — no Config/*.xcconfig is applied to this configuration"
    exit 0
fi

echo "note: Payabli SDK linkage = ${LINKAGE}"

case "$LINKAGE" in
source)
    echo "note: SDK compiles from Package.swift as part of this build"
    ;;

xcframework)
    # Deliberately verify-and-fail rather than build. build_release_frameworks.sh
    # is six xcodebuild archive invocations, so running it per build would be
    # unusable, and running it silently would ship stale artifacts.
    XCF_DIR="${SRCROOT}/../../build/xcframeworks"
    REQUIRED=(PayabliSDKCore PayabliSDKTapToPay PayabliSDKPayInPaymentFlow)

    missing=()
    for name in "${REQUIRED[@]}"; do
        [[ -d "${XCF_DIR}/${name}.xcframework" ]] || missing+=("$name")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "error: PAYABLI_SDK_LINKAGE=xcframework but these are missing from ${XCF_DIR}: ${missing[*]}"
        echo "error: build them first —  ./Scripts/build_release_frameworks.sh  (run from the ios/ root)"
        exit 1
    fi

    # Stale artifacts are worse than absent ones: the build would succeed against
    # code that no longer exists.
    newest_source="$(find "${SRCROOT}/../../Sources" -name '*.swift' -newer "${XCF_DIR}/PayabliSDKCore.xcframework" -print -quit 2>/dev/null || true)"
    if [[ -n "$newest_source" ]]; then
        echo "error: XCFrameworks are older than Sources/ (e.g. ${newest_source})"
        echo "error: rebuild them —  ./Scripts/build_release_frameworks.sh"
        exit 1
    fi

    echo "error: xcframework linkage is not wired yet."
    echo "error: a build configuration cannot drop a Swift package product —"
    echo "error: packageProductDependencies hangs off the target, not the configuration,"
    echo "error: so this build would still link PayabliSDKExampleAggregate from source."
    echo "error: making this real needs a second target whose packageProductDependencies"
    echo "error: is empty and which links the XCFrameworks instead."
    exit 1
    ;;

*)
    echo "error: PAYABLI_SDK_LINKAGE='${LINKAGE}' is not recognised (expected 'source' or 'xcframework')"
    exit 1
    ;;
esac
