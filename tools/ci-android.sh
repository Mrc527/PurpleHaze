#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
release_build=${1:-false}
python3 scripts/verify-vendor.py
python3 - <<'PY'
import hashlib
from pathlib import Path
expected='cb0da6751c2b753a16ac168bb354870ebb1e162e9083f116729cec9c781156b8'
assert hashlib.sha256(Path('android/gradle/wrapper/gradle-wrapper.jar').read_bytes()).hexdigest()==expected, 'Gradle wrapper checksum mismatch'
PY
export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/29.0.14206865"
printf 'sdk.dir=%s\n' "$ANDROID_HOME" > android/local.properties
JOBS=2 ./android/scripts/build-openssl.sh
(
  cd android
  ./gradlew --no-daemon assembleDebug assembleDebugAndroidTest testDebugUnitTest lintDebug
  if [[ "$release_build" == true ]]; then ./gradlew --no-daemon assembleRelease bundleRelease; fi
)
mkdir -p artifacts/android
if [[ "$release_build" == true ]]; then
  cp android/build/outputs/apk/release/*-unsigned.apk artifacts/android/PurpleHaze-Android-unsigned.apk
  cp android/build/outputs/bundle/release/*.aab artifacts/android/PurpleHaze-Android-unsigned.aab
else
  cp android/build/outputs/apk/debug/*.apk artifacts/android/PurpleHaze-Android-debug.apk
fi
for apk in artifacts/android/*.apk; do "$ANDROID_HOME/build-tools/35.0.0/zipalign" -c -P 16 4 "$apk"; done
