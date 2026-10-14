#!/bin/bash
# Builds both woowtech editions (on-premise and cloud) back to back.
#
# The cloud edition only compiles under the CLOUD_EDITION flag, so a change
# that builds fine for one edition can silently break the other. Run this
# script locally before pushing; any failed build exits non-zero.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_ROOT="${DERIVED_DATA_ROOT:-$REPO_ROOT/build/editions}"

build_edition() {
    local edition="$1"
    shift
    echo "==> Building edition: $edition"
    xcodebuild \
        -project "$REPO_ROOT/HomeAssistant.xcodeproj" \
        -scheme App-Debug \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED_DATA_ROOT/$edition" \
        -skipPackagePluginValidation \
        -skipMacroValidation \
        CODE_SIGNING_ALLOWED=NO \
        "$@" \
        build
    echo "==> $edition build succeeded"
}

build_edition onprem
build_edition cloud -xcconfig "$REPO_ROOT/Configuration/WoowtechCloud.xcconfig"

echo "==> Both editions built successfully"
