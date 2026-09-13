#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly package_root="${repository_root}/ForgeRuleCore"

echo "== Swift toolchain =="
swift --version
echo
echo "== Xcode toolchain =="
xcodebuild -version
echo
echo "== Host platform =="
sw_vers
uname -a
echo

echo "== Test governance =="
"${script_directory}/check-test-governance.sh"
echo

cd "${package_root}"
echo "== Clean dependency resolution =="
swift package reset
swift package resolve
echo

echo "== Debug build and tests =="
swift build
swift test
echo

echo "== Release build and tests =="
swift build -c release
swift test -c release
echo

echo "== Strict concurrency compile and tests =="
swift test \
    -Xswiftc -strict-concurrency=complete \
    -Xswiftc -warnings-as-errors
echo

echo "== Generic iOS 15 arm64 build =="
readonly ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
swift build \
    --triple arm64-apple-ios15.0 \
    --sdk "${ios_sdk}" \
    -Xswiftc -target \
    -Xswiftc arm64-apple-ios15.0
echo

echo "== Production coverage gate =="
"${script_directory}/coverage.sh"
