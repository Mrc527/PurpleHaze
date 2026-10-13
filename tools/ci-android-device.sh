#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
# avdmanager and emulator versions may choose different default configuration homes.
# Pin all supported homes so both tools discover the same AVD registry.
export ANDROID_USER_HOME="$RUNNER_TEMP/purplehaze-android/.android"
export ANDROID_EMULATOR_HOME="$ANDROID_USER_HOME"
export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
export ANDROID_SDK_HOME="$RUNNER_TEMP/purplehaze-android"
mkdir -p "$ANDROID_AVD_HOME"
sdkmanager 'system-images;android-35;google_apis;x86_64' 'emulator'
printf 'no\n' | avdmanager create avd --force --name purplehaze-ci --package 'system-images;android-35;google_apis;x86_64' --device pixel_6 --path "$ANDROID_AVD_HOME/purplehaze-ci.avd"
emulator -list-avds | grep -Fx purplehaze-ci
[[ -e /dev/kvm ]] || { echo 'KVM is required for Android device tests' >&2; exit 1; }
sudo chmod a+rw /dev/kvm
emulator -avd purplehaze-ci -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader_indirect > "$RUNNER_TEMP/android-emulator.log" 2>&1 &
emulator_pid=$!
trap 'adb -s emulator-5554 emu kill >/dev/null 2>&1 || true; kill "$emulator_pid" >/dev/null 2>&1 || true' EXIT
booted=false
for attempt in {1..90}; do
  if ! kill -0 "$emulator_pid" 2>/dev/null; then
    cat "$RUNNER_TEMP/android-emulator.log"
    echo 'Android emulator exited before boot' >&2
    exit 1
  fi
  boot_status=$(timeout 5 adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
  if [[ "$boot_status" == 1 ]]; then booted=true; break; fi
  sleep 2
done
[[ "$booted" == true ]] || { cat "$RUNNER_TEMP/android-emulator.log"; exit 1; }
adb -s emulator-5554 shell input keyevent 82
for setting in window_animation_scale transition_animation_scale animator_duration_scale; do adb -s emulator-5554 shell settings put global "$setting" 0; done
cd android
./gradlew --no-daemon connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=ch.visin.purplehaze.ProfileSecurityTest,ch.visin.purplehaze.ProfileEditorTest
