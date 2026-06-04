#!/usr/bin/env bash
#
# render_public_manifests.sh
# --------------------------
# Renders the three public-repo files (Package.swift, PayabliSDK.podspec,
# README.md) from their templates into build/public/, substituting
# VERSION, S3_PUBLIC_HOST, and the per-product sha256 checksums.
#
# Environment (required):
#   VERSION                  e.g. 1.0.247-qa
#   S3_PUBLIC_HOST           e.g. payabli-public-objects-qa.s3.amazonaws.com
#   CORE_SHA256              sha256 of payabli-ios-sdk-core-${VERSION}.zip
#   TAPTOPAY_SHA256          sha256 of payabli-ios-sdk-taptopay-${VERSION}.zip
#   PAYIN_PAYMENT_FLOW_SHA256 sha256 of payabli-ios-sdk-payin-payment-flow-${VERSION}.zip
#   CARD_READER_CORE_SHA256  sha256 of payabli-ios-sdk-card-reader-core-${VERSION}.zip
#
# PayInPaymentFlow is rendered as an opt-in public product using
# PAYIN_PAYMENT_FLOW_SHA256. The older PAYIN_SHA256 placeholder is no longer
# used by the public templates.
#
# Inputs (repo-relative):
#   .github/templates/public-Package.swift.tmpl
#   .github/templates/public-PayabliSDK.podspec.tmpl
#   .github/templates/public-README.md.tmpl
#
# Outputs:
#   build/public/Package.swift
#   build/public/PayabliSDK.podspec
#   build/public/README.md
#
# These rendered files are picked up by Scripts/push_to_public_repo.sh and
# committed into the public mirror.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

missing=()
for var in VERSION S3_PUBLIC_HOST CORE_SHA256 TAPTOPAY_SHA256 PAYIN_PAYMENT_FLOW_SHA256 CARD_READER_CORE_SHA256; do
    if [[ -z "${!var:-}" ]]; then
        missing+=("$var")
    fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: missing required environment variable(s): ${missing[*]}" >&2
    exit 1
fi

TEMPLATE_DIR="$REPO_ROOT/.github/templates"
OUTPUT_DIR="$REPO_ROOT/build/public"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# envsubst substitutes only the variables we pass, so unrelated `$`-strings
# inside the templates are left intact.
VARS='${VERSION} ${S3_PUBLIC_HOST} ${CORE_SHA256} ${TAPTOPAY_SHA256} ${PAYIN_PAYMENT_FLOW_SHA256} ${CARD_READER_CORE_SHA256}'

render() {
    local template="$1" output="$2"
    if [[ ! -f "$template" ]]; then
        echo "error: template not found: $template" >&2
        exit 1
    fi
    envsubst "$VARS" < "$template" > "$output"
    echo "[render] ${template#$REPO_ROOT/} -> ${output#$REPO_ROOT/}"
}

render "$TEMPLATE_DIR/public-Package.swift.tmpl"       "$OUTPUT_DIR/Package.swift"
render "$TEMPLATE_DIR/public-PayabliSDK.podspec.tmpl"  "$OUTPUT_DIR/PayabliSDK.podspec"
render "$TEMPLATE_DIR/public-README.md.tmpl"           "$OUTPUT_DIR/README.md"

# Sanity: no remaining un-substituted `${...}` markers in any output file
# (envsubst silently leaves them if a variable was empty — we catch that here
# before a broken manifest reaches the public repo).
leftover=$(grep -REn '\$\{[A-Z_]+\}' "$OUTPUT_DIR" || true)
if [[ -n "$leftover" ]]; then
    echo "error: un-substituted placeholders remain in rendered output:" >&2
    echo "$leftover" >&2
    exit 1
fi

echo "[render] all manifests rendered successfully into $OUTPUT_DIR"
