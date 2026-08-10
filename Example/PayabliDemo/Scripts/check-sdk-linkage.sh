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
    # Fails every time, on purpose, rather than quietly building from source.
    #
    # Which products a target links is set on the target, so no configuration can
    # unlink the package: this build would link the package sources and any
    # framework it found. A second target that links the frameworks instead is
    # what makes this mode real, and there isn't one yet.
    #
    # The checks this branch will need once that target exists — the frameworks
    # are present, and they are newer than Sources/ — are deliberately not here.
    # They cannot run ahead of the target, and code that cannot run is not proof
    # that it works.
    echo "error: PAYABLI_SDK_LINKAGE=xcframework is not wired up, so this build cannot succeed."
    echo "error: it needs a target that links the XCFrameworks instead of the package, and there isn't one."
    echo "error: build with the Debug configuration."
    exit 1
    ;;

*)
    echo "error: PAYABLI_SDK_LINKAGE='${LINKAGE}' is not recognised (expected 'source' or 'xcframework')"
    exit 1
    ;;
esac
