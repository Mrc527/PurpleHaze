# PurpleHaze

PurpleHaze is an iodine DNS-tunnel client for **Android and iOS**, with a common
brand, named connection profiles and an optional encrypted server-proxy mode.
Both apps compile the same modified iodine client engine from `vendor/iodine`.
This is an independent fork of PurpleHaze and AndIodine.

| Component | Location | Build and usage |
|---|---|---|
| Android app, Android 8+ | [`android/`](android/) | [Android guide](android/README.md) |
| iPhone/iPad app, iOS 15+ | [`ios/`](ios/) | [iOS guide](ios/README.md) |
| Shared iodine client | [`vendor/iodine/`](vendor/iodine/) | [Provenance and updates](vendor/iodine/README.md) |
| Repository and CI | [Monorepo guide](docs/monorepo.md) | [Workflows](.github/workflows/) |

Each profile has its own authentication, resolver, DNS, routing and transport
settings. **Encrypted** mode requires a 32-byte server key, entered as Base64,
and uses protocol `0x602` with automatic traffic-key rotation. **Legacy** mode
explicitly selects the unencrypted `0x502` protocol. A missing encryption key
never silently changes the selected mode.

**Server proxy** requires the matching modified iodine server and its proxy
helper. It routes IPv4 TCP, UDP and DNS through the encrypted tunnel; IPv6 is
blocked while connected. Stock upstream iodine servers work only with Legacy
mode. The server and command-line client are maintained separately in
[Mrc527/iodine](https://github.com/Mrc527/iodine).

## Build locally

```sh
git clone https://github.com/Mrc527/PurpleHaze.git
cd PurpleHaze
python3 scripts/verify-vendor.py
```

Android requires JDK 17, Android SDK 35 and NDK `29.0.14206865`:

```sh
cd android
./scripts/build-openssl.sh
./gradlew --no-daemon assembleDebug testDebugUnitTest lintDebug
```

For iOS, use a Mac with full Xcode and follow the [signing guide](ios/README.md#sign-and-install):

```sh
cd ios
./build-openssl.sh iphoneos
xcodebuild -project PurpleHaze.xcodeproj -scheme 'Purple Haze' \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build-ios/device CODE_SIGNING_ALLOWED=NO build
```

Run each platform block from the repository root. OpenSSL 3.5.9 downloads are
verified against a pinned SHA-256. Libraries, signing material, server keys and
build outputs are not committed.

CI builds and tests the apps and provides downloadable artifacts. Version tags
publish unsigned Android APK/AAB and iOS app ZIP files with checksums; manual
release runs default to a draft. This is **not App Store or Google Play
deployment**: release packages require signing, and Android debug signing is for
development.
See the [CI and release guide](docs/monorepo.md#ci-and-release-artifacts) for the
artifact and signing boundaries.

## Existing installations and checkouts

Android retains application ID `ch.visin.andiodine`, its profile database and
Keystore identity. iOS retains its existing bundle and shared-Keychain identities;
the previous single configuration migrates to a named profile. Update with the
same signing identity to preserve access to installed credentials.

The monorepo preserves both original Git histories. Platform sources now live
under `android/` and `ios/`; the shared engine has a single canonical location.
[Migration details](docs/monorepo.md#history-and-directory-migration) explain how
to update local tools and keep ignored signing files outside Git.

DNS tunnelling has network-dependent throughput and reliability. Disconnecting
restores ordinary networking; these apps do not provide a persistent kill switch
or a supervised-device always-on policy. Simulator and emulator tests do not
replace physical-device routing checks.

## Attribution and licenses

PurpleHaze derives from [DullJZ/PurpleHaze](https://github.com/DullJZ/PurpleHaze)
and [osy/PurpleHaze](https://github.com/osy/PurpleHaze); Android derives from
[AndIodine](https://gitlab.com/andiodine/andiodine); the engine derives from
[yarrick/iodine](https://github.com/yarrick/iodine). Licenses remain scoped to the
original components. Read the [license overview](LICENSE), preserved platform
licenses and bundled notices before distributing a build.
