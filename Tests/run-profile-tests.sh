#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output="$(mktemp -d "${TMPDIR:-/tmp}/purplehaze-tests.XXXXXX")"
trap 'rm -rf "$output"' EXIT HUP INT TERM
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -swift-version 5 \
    Extension/IodineSettings.swift Extension/Credentials.swift \
    PurpleHaze/ConnectionProfile.swift PurpleHaze/ProfileStore.swift \
    Tests/ProfileStoreTests.swift -o "$output/profile-tests"
"$output/profile-tests"
