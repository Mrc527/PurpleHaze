#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
sdkmanager 'system-images;android-35;google_apis;x86_64' 'emulator'
printf 'no\n' | avdmanager create avd --force --name purplehaze-ci --package 'system-images;android-35;google_apis;x86_64' --device pixel_6
[[ -e /dev/kvm ]] || { echo 'KVM is required for Android device tests' >&2; exit 1; }
sudo chmod a+rw /dev/kvm
emulator -avd purplehaze-ci -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader_indirect > "$RUNNER_TEMP/android-emulator.log" 2>&1 &
trap 'adb -s emulator-5554 emu kill >/dev/null 2>&1 || true' EXIT
timeout 180 adb -s emulator-5554 wait-for-device
booted=false
for attempt in {1..90}; do
  if [[ "$(adb -s emulator-5554 shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]; then booted=true; break; fi
  sleep 2
done
[[ "$booted" == true ]] || { cat "$RUNNER_TEMP/android-emulator.log"; exit 1; }
adb -s emulator-5554 shell input keyevent 82
for setting in window_animation_scale transition_animation_scale animator_duration_scale; do adb -s emulator-5554 shell settings put global "$setting" 0; done
cd android
./gradlew --no-daemon connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=ch.visin.purplehaze.ProfileSecurityTest,ch.visin.purplehaze.ProfileEditorTest
