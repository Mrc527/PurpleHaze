#!/bin/sh
# ISC license. Static, checksum-verified OpenSSL for the Android NDK.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk/29.0.14206865}
case $(uname -s) in Darwin) host=darwin-x86_64 ;; Linux) host=linux-x86_64 ;; *) echo 'Use Linux/macOS to cross-build OpenSSL' >&2; exit 2 ;; esac
export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$host/bin:$PATH"
version=3.5.9
sha=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
cache="$root/.deps/openssl"
mkdir -p "$cache"
archive="$cache/openssl-$version.tar.gz"
if [ ! -f "$archive" ]; then
  curl --fail --location --retry 3 "https://www.openssl.org/source/openssl-$version.tar.gz" -o "$archive.download"
  mv "$archive.download" "$archive"
fi
printf '%s  %s\n' "$sha" "$archive" | shasum -a 256 -c -
if [ ! -d "$cache/openssl-$version" ]; then tar -xzf "$archive" -C "$cache"; fi
for abi in ${ABIS:-arm64-v8a armeabi-v7a x86_64 x86}; do
  case "$abi" in
    arm64-v8a) target=android-arm64 ;; armeabi-v7a) target=android-arm ;;
    x86_64) target=android-x86_64 ;; x86) target=android-x86 ;; *) exit 2 ;;
  esac
  prefix="$root/.deps/$abi"
  if [ -f "$prefix/lib/libssl.a" ] && [ -f "$prefix/lib/libcrypto.a" ]; then continue; fi
  mkdir -p "$cache/build-$abi"
  cd "$cache/build-$abi"
  perl "../openssl-$version/Configure" "$target" -D__ANDROID_API__=26 no-shared no-tests no-module no-apps \
    --prefix="$prefix" --libdir=lib
  make -j "${JOBS:-6}" build_libs
  make install_dev
  cp "../openssl-$version/LICENSE.txt" "$prefix/LICENSE-OpenSSL.txt"
done
