#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify-vendor.py
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_26.3.app/Contents/Developer}"
xcodebuild -version
./ios/Tests/run-profile-tests.sh
./ios/build-openssl.sh iphoneos
xcodebuild -project ios/PurpleHaze.xcodeproj -scheme 'Purple Haze' -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath ios/build-ios/ci-device \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p artifacts/ios
ditto -c -k --keepParent 'ios/build-ios/ci-device/Build/Products/Release-iphoneos/Purple Haze.app' \
  artifacts/ios/PurpleHaze-iOS-unsigned.app.zip
