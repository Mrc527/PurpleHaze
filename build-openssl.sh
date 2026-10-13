#!/bin/sh
# Build pinned, checksum-verified static OpenSSL for Xcode's device/simulator SDK.
set -eu
sdk=${1:-iphoneos}
case "$sdk" in
  iphoneos) target=ios64-xcrun; minimum=-miphoneos-version-min=15.0 ;;
  iphonesimulator) target=iossimulator-arm64-xcrun; minimum=-mios-simulator-version-min=15.0 ;;
  *) echo 'Usage: ./build-openssl.sh [iphoneos|iphonesimulator]' >&2; exit 2 ;;
esac
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
version=3.5.9
sha=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
cache="$root/build-ios/openssl"
archive="$cache/openssl-$version.tar.gz"
prefix="$root/build-ios/deps/$sdk"
mkdir -p "$cache" "$cache/$sdk"
if [ ! -f "$archive" ]; then
  curl --fail --location --retry 3 "https://www.openssl.org/source/openssl-$version.tar.gz" -o "$archive.download"
  mv "$archive.download" "$archive"
fi
printf '%s  %s\n' "$sha" "$archive" | shasum -a 256 -c -
if [ ! -d "$cache/openssl-$version" ]; then
  tar -xzf "$archive" -C "$cache"
fi
cd "$cache/$sdk"
perl "../openssl-$version/Configure" "$target" no-shared no-tests "$minimum" --prefix="$prefix" --libdir=lib
make -j "${JOBS:-4}" build_libs
make install_dev
