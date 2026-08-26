#!/usr/bin/env bash
#
# Keeps every SDK call in the sample app inside one directory.
#
#   ./Scripts/check-example-sdk-boundary.sh
#
# The sample app is the first thing an integrator reads, and it is only worth
# reading if the calls are findable. Example/PayabliDemo/SDK/ holds all of them,
# and this is what makes that true rather than aspirational: a screen that reaches
# for an SDK type fails here instead of during review.
#
# The counterpart on Android is example/src/main/java/com/payabli/example/app/sdk/,
# where the same property holds and is stated in PayInFlowHandle.kt: outside that
# package nothing names an SDK type, which is what makes the package the whole of
# the integration rather than most of it.
#
# Test targets are outside the rule. DeviceTests drives the SDK directly against a
# live environment and FlowTests asserts on the SDK's own session states, so both
# name SDK types on purpose.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP="Example/PayabliDemo"

leaks="$(
    grep -rl '^import PayabliSDK' --include='*.swift' "$APP" 2>/dev/null \
        | grep -v "^$APP/SDK/" \
        | grep -vE "^$APP/(DeviceTests|FlowTests|UITests)/" \
        | sort
)"

if [ -z "$leaks" ]; then
    count="$(find "$APP/SDK" -name '*.swift' | wc -l | tr -d ' ')"
    printf 'Example SDK boundary holds: %s files under %s/SDK, and nothing outside it imports the SDK.\n' \
        "$count" "$APP"
    exit 0
fi

printf 'The sample app calls the SDK from outside %s/SDK:\n\n' "$APP"
printf '%s\n' "$leaks" | sed 's/^/  /'
cat <<'EOF'

Move the call into Example/PayabliDemo/SDK/ and hand the screen one of this app's
own types instead. PaymentFormHost.swift and PayInFlowHandle.swift are the pattern:
the SDK type stays in the group, the screen gets an answer.
EOF
exit 1
