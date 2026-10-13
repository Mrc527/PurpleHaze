# Working in the PurpleHaze monorepo

## Layout and ownership

- `android/`: Gradle project, Android screens, SQLite/Keystore profiles and JNI adapters.
- `ios/`: Xcode project, UIKit screens, profile metadata/Keychain storage and Packet Tunnel extension.
- `vendor/iodine/`: the canonical modified iodine client engine, its license and source manifest.
- `scripts/`: checks and shared automation.
- `.github/workflows/`: CI and release packaging for both platforms.

Both apps use the same C engine directly. Platform configuration, logging,
packet interfaces and native-language bridges stay under their platform folder.
The server and CLI are not embedded in this repository.

## History and directory migration

The iOS and Android histories are joined by a Git merge, retaining original
commits and authors. This is not a squashed source import. Historical commits
keep their historical paths; current platform paths are `ios/` and `android/`.
For example:

```sh
git log --all --oneline --graph
git log --follow -- ios/PurpleHaze/AppDelegate.swift
git log --follow -- android/build.gradle
```

Existing iOS checkout scripts must now enter `ios/` before invoking Xcode or
`build-openssl.sh`. Android scripts enter `android/` before invoking Gradle.
Open `ios/PurpleHaze.xcodeproj` in Xcode or import `android/` in Android Studio.

Ignored local files are not migrated by Git. Preserve your existing
`CodeSigning.xcconfig` as `ios/CodeSigning.xcconfig` and Android SDK path as
`android/local.properties`. Existing dependency caches may be rebuilt in
`ios/build-ios/` and `android/.deps/`; they must not be staged. A local archived
checkout or compatibility symlink is a workstation convenience, not a build
requirement. No sibling repository, symlink or submodule is required by CI.

Application identifiers remain unchanged during the repository move. Updating
an installed app still requires the same signing identity; moving files does
not migrate or export device Keychain/Keystore contents.

## Updating the shared engine

Edit `vendor/iodine/src` only; do not recreate platform engine copies.
Before and after intentional engine changes, run:

```sh
python3 scripts/verify-vendor.py
# Only after reviewing an intentional source/license change:
python3 scripts/verify-vendor.py --update
```

The manifest proves which source snapshot is checked in, not that a cryptographic
change is correct. Compile and test both platforms after changing shared code.
Protocol or proxy changes also require interoperability checks against the
matching server, in both DNS-only and direct-UDP modes when applicable.

The [vendor provenance](../vendor/iodine/README.md) records the source revision,
local modifications and platform-specific adapters. Keep this description and
all source license notices accurate when updating the engine.

## Local validation

Use the full setup instructions in the [Android guide](../android/README.md)
and [iOS guide](../ios/README.md). From the repository root:

```sh
python3 scripts/verify-vendor.py
(cd android && ./gradlew --no-daemon assembleDebug testDebugUnitTest lintDebug)
(cd ios && ./Tests/run-profile-tests.sh)
```

Android instrumentation tests require an emulator/device. Live server tests are
opt-in and require a key copied into app-private test storage; remove it after
the test. iOS UI tests use a dedicated simulator, synthetic profile credentials
and real simulator Keychain storage. They do not start a VPN. Their known
simulator-only Network Extension startup limitation is documented in the iOS
guide. Test actual VPN consent, routes, DNS, reconnects and network changes on
signed physical devices before claiming a device is supported.

## CI and release artifacts

The [Android CI](../.github/workflows/android-ci.yml) and
[iOS CI](../.github/workflows/ios-ci.yml) workflows run for relevant pull requests,
changes pushed to `main`, and manual dispatch. Shared engine and CI-tool changes
run both platforms. Android validates all four ABIs, unit tests, lint and profile
security/editor tests on an Android 15 emulator. iOS runs the profile regression
suite and builds a device app without signing; its simulator UI tests remain a
separate local check.

Normal CI uploads `android-debug` (development-signed APK),
`android-test-reports` and `ios-unsigned-app` artifacts, retained for 14 days.
It needs no production signing secrets or private tunnel server. Dependency
source archives and the Gradle wrapper are checksum-verified; external Actions
are pinned to full commit IDs. The workflows use read-only repository permission
except for the release publication job.

The [release workflow](../.github/workflows/release.yml) runs when a `v*` tag is
pushed and accepts version tags such as `v1.9.0` or `v1.9.0-rc.1`. It resolves the
existing tag to an exact commit, rebuilds and validates both platforms, then
publishes a GitHub Release only after both builds pass. Tag-triggered publication
is public; a prerelease tag containing `-` is marked as a prerelease. Manual
release dispatch takes an existing version tag and defaults to a draft.

From the repository root, use the checked-in monitor wrapper:

```sh
GH_REPO=Mrc527/PurpleHaze node tools/ci_monitor.cjs runs
GH_REPO=Mrc527/PurpleHaze node tools/ci_monitor.cjs dispatch release.yml -f tag=v1.9.0 -f draft=true
```

Releases contain only these build files and their `SHA256SUMS`:

- `PurpleHaze-Android-unsigned.apk`
- `PurpleHaze-Android-unsigned.aab`
- `PurpleHaze-iOS-unsigned.app.zip`

These are **unsigned packages, not store submissions**. Android release APK/AAB
files need the appropriate release keystore before installation or publishing.
The iOS ZIP contains an unsigned `.app`, not an installable IPA; it requires Apple
signing, provisioning for the app and VPN extension, and a separate export step.
The workflows do not publish to Google Play or the App Store.

Android debug APKs use a development signing identity that can differ between
CI runs; they cannot replace an installation signed with another key. Production
keystores, Apple certificates and provisioning profiles belong in a separately
configured protected signing process. No server keys or local signing files are
included. The release notes record the source commit; retain `SHA256SUMS` when
comparing downloaded outputs. To publish a new version, create and push its
reviewed version tag; do not move an already published release tag.

## Contributions

Keep platform changes in their folders and protocol changes in the shared engine.
Include the behavior being changed and the validation actually performed in each
pull request. Preserve upgrade paths, installed application IDs, explicit
Encrypted/Legacy selection, per-profile credential isolation and fail-closed
handling of missing keys. Use synthetic credentials in tests and screenshots.

Do not edit generated build outputs or duplicate the engine to make one platform
compile. Commit source and dependency pin/checksum changes together. Preserve the
component-specific licenses described in the [license overview](../LICENSE).
