# PurpleHaze for Android — encrypted iodine 0x602

PurpleHaze-branded Android client for the custom encrypted iodine server, based on
[AndIodine](https://gitlab.com/andiodine/andiodine) commit
`82fcf7ba697c9b8d562e2bf4b6d5ded4c606da9d` (3 September 2024).
This is an independent adaptation, not an official iodine Android client.
Android 8.0 or newer; no root required. Application ID: `ch.visin.andiodine`,
so existing installs of our AndIodine fork upgrade in place and retain profiles and Keystore credentials. It can also coexist with upstream AndIodine.

The Android implementation now uses the `ch.visin.purplehaze` namespace, a profile dashboard and a native profile editor with explicit Save/Cancel. The shared PurpleHaze palette and icon match the iOS app. Each profile stores its own credentials, routing and transport options. Disconnect before editing or switching profiles. Existing database versions 1 and 2 migrate automatically to schema 4, retaining authentication mode. New profiles require an explicit encrypted/legacy choice and default to encryption; an empty key never silently changes that choice.

## Configure a connection

1. Add a profile, enter its name and the iodine top domain.
2. Enter the server's **Shared key (Base64)**: the Base64 representation of the
   same 32-byte binary key used by `iodine -K` / `iodined -K`. Leave the legacy
   password empty. Credentials are encrypted in the profile database using
   Android Keystore and excluded from backups. No server key is bundled.
3. Enable **Server proxy (TCP / UDP / DNS)** to route device IPv4 traffic through
   the encrypted tunnel and the server proxy, regardless of the Default Route
   checkbox. This requires a server with the proxy helper enabled.
4. Optionally set Tunnel Nameserver to a reachable resolver or the iodine server's
   public IPv4 address. Leave Request Type on AUTODETECT initially.
5. Connect and grant Android's VPN permission. Notifications show connection state
   and provide a Disconnect action.

Proxy mode supports TCP (including HTTP and HTTPS), UDP and DNS. It uses the
server's authenticated SOCKS5 gateway transparently; no per-app proxy setup is
needed. The server's HTTP/CONNECT and SOCKS5 listeners are also advertised by the
handshake. Proxy DNS defaults to `1.1.1.1`; SET_CUSTOM overrides it. IPv6 is blocked
while the VPN is connected, because this iodine protocol carries IPv4 only.
ICMP is not forwarded to the Internet by the proxy. Android exemptions for system
traffic and traffic shared via tethering are outside this VpnService's scope.

Selecting **Legacy** with proxy disabled uses the original
**unencrypted 0x502** protocol and legacy password. Supplying a key selects 0x602
and never silently downgrades. Proxy without a key, or key plus legacy password,
is rejected. Session keys rotate without a scheduled hourly reconnect.

Raw Mode attempts direct UDP, falling back to DNS transport when unavailable.
Leave it off to force DNS tunnelling. Throughput and reliability depend on the
resolver/network; this is still a DNS tunnel. Changing Wi-Fi/mobile networks
requires reconnecting. Disconnecting or stopping the app restores normal Android
routing; this build does not implement always-on VPN or a persistent kill switch.

## Build

Install JDK 17, Android SDK platform 35, Android build tools 35.0.0 and
NDK `29.0.14206865`. Point `local.properties` at your SDK (`sdk.dir=...`).
On macOS or Linux:

```sh
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=/path/to/android-sdk
export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/29.0.14206865"
./scripts/build-openssl.sh
./gradlew --no-daemon assembleDebug testDebugUnitTest lintDebug
```

The OpenSSL script downloads version 3.5.9, verifies its pinned SHA-256 and builds
static libraries for ARM64, ARMv7, x86_64 and x86. Generated libraries/cache live
in ignored `.deps/`. Native libraries support 16 KB page alignment.

Install `build/outputs/apk/debug/PurpleHazeAndroid-debug.apk` using Android's package
installer or `adb install -r build/outputs/apk/debug/PurpleHazeAndroid-debug.apk`.
This is a development-signed debug APK. Distribution requires your own release
signing configuration; signing keys must not be committed.

## Verification

`testDebugUnitTest` tests shared-key parsing and authentication-mode validation.
`connectedDebugAndroidTest` checks encrypted credential storage/tamper rejection,
v1/v2 profile migration, profile CRUD/credential isolation, editor save/rotation and JNI secure/legacy configuration. Live networking tests
are opt-in and otherwise skipped.

For a disposable emulator, install the app and androidTest APK, grant the VPN
permission, then put the server's binary key in app-private `files/test-server.key`
using `adb exec-in run-as ch.visin.andiodine`. Never embed it in test sources.
Run the instrumented test with `live.server`, `live.domain`, `live.egress` and
`live.raw` arguments:

```sh
adb shell am instrument -w \
  -e class ch.visin.purplehaze.LiveProxyTest \
  -e live.server SERVER_IPV4 -e live.domain TUNNEL_DOMAIN \
  -e live.egress EXPECTED_PUBLIC_IPV4 -e live.raw false \
  ch.visin.andiodine.test/androidx.test.runner.AndroidJUnitRunner
```

Remove `files/test-server.key` afterwards. The test checks HTTPS, public egress IP,
UDP DNS and IPv6 blocking, and deletes its temporary profile on completion.
On 13 October 2026, the refactored app passed 4 unit tests, 7 device tests covering
credentials, migrations, JNI, profile CRUD and editor save/rotation, plus an opt-in
screenshot fixture. Live proxy tests against mi-gtw passed in both DNS-only
and direct-UDP mode (HTTPS, UDP DNS, public egress IP and IPv6 blocking).
Physical devices, older Android versions and long-duration sessions still need
verification. Lint has no errors; remaining warnings concern tool versions, compatibility checks and launcher metadata.

Native source provenance is recorded in [jni/iodine/README.android.md](jni/iodine/README.android.md).
The original German manuals in `doc/` describe the upstream legacy client.
OpenSSL's license is in [third-party/LICENSE-OpenSSL.txt](third-party/LICENSE-OpenSSL.txt)
and the app's About dialog.

# Authors and License
Android Iodine Copyright (c) 2016 Yves Fischer <yvesf+andiodine@xapek.org> and contributors.  
Same license as iodine.

Iodine Copyright (c) 2006-2009 Bjorn Andersson <flex@kryo.se>, Erik Ekman <yarrick@kryo.se>  
Also major contributions by Anne Bezemer.

Permission to use, copy, modify, and distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.


MD5 implementation by L. Peter Deutsch (license and source in jni/iodine/src/md5.[ch])  
Copyright (C) 1999, 2000, 2002 Aladdin Enterprises.  All rights reserved.

Branding/icon attribution: [PurpleHaze](https://github.com/DullJZ/PurpleHaze), Apache 2.0; see `third-party/LICENSE-PurpleHaze.txt` and in-app notices.
