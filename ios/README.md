# PurpleHaze for encrypted iodine

Based on [DullJZ/PurpleHaze](https://github.com/DullJZ/PurpleHaze), commit
`c310fd540c8fc05adb12c0e42023aedd930e9037` (Apache-2.0, derived from osy/PurpleHaze).
The Xcode project builds the modified iodine client shared with Android in
[`../vendor/iodine/src`](../vendor/iodine/src).
No sibling checkout or Git submodule is required. Original app attribution and
licenses are preserved in `LICENSE` and the bundled `ThirdPartyNotices.txt`.

Requires a Mac with full Xcode, iOS SDK, and iOS 15 or later on an arm64 iPhone
or iPad. OpenSSL 3.5.9 is linked statically. Rebuild the app when updating it.

## Build

Clone this monorepo and enter the iOS directory:

```sh
git clone https://github.com/Mrc527/PurpleHaze.git
cd PurpleHaze/ios
```

Build dependencies and the app:

```sh
./build-openssl.sh iphoneos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PurpleHaze.xcodeproj -scheme 'Purple Haze' \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build-ios/device CODE_SIGNING_ALLOWED=NO build
```

Output: `build-ios/device/Build/Products/Release-iphoneos/Purple Haze.app`,
including `PlugIns/Iodine.appex`. This command produces an **unsigned build**;
it cannot be installed on a physical device as-is. No server credentials are
included. Dependencies and build products are gitignored under `build-ios/`.

For an Apple Silicon simulator, build dependencies with `iphonesimulator`, then
use `-sdk iphonesimulator -destination 'generic/platform=iOS Simulator'` and a
separate derived-data directory. The VPN must still be tested on a signed,
physical device; simulator UI tests do not prove Network Extension operation.

## Sign and install

Copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig`, set your development
team and unique bundle prefix, and open `PurpleHaze.xcodeproj` in Xcode.
Use a team/provisioning profiles supporting the Packet Tunnel Network Extension,
App Groups and Keychain Sharing capabilities on both targets. Xcode must resolve:

- `<prefix>.Purple-Haze` for the app;
- `<prefix>.Purple-Haze.Iodine` for the extension;
- `group.<prefix>.Purple-Haze` for shared logs;
- `<AppIdentifierPrefix><prefix>.Purple-Haze.credentials` for shared Keychain access.

Select the physical device and build/run with signing enabled. Archive and export
through Xcode for distribution. Use your own signing identity and profiles.
Validate shared Keychain access and VPN routing on the signed device build.

## Connect

Create a named profile in the app, enter the delegated tunnel domain and choose
**Encrypted** or **Legacy** authentication. Each profile owns its server, transport,
DNS, routing and credential settings. Select a saved profile before connecting;
editing, deleting and switching profiles is disabled while the VPN is active.

For encrypted mode, paste the Base64 representation of the server's existing
**32-byte binary key** into **Shared key**. Convert the file locally with
`openssl base64 -A -in /path/to/iodine.key` and transfer it over a trusted channel.
Do not generate a different key for this client. The client requests `0x602`, with
TLS authentication, encrypted packets and automatic traffic-key rotation. An
invalid or missing key never falls back to plaintext.

Choose **Legacy** explicitly to use **unencrypted `0x502`**, and enter the server's
legacy password (at most 32 UTF-8 bytes). The server must allow legacy sessions.
This matches the command-line client's behavior without `-K`. A profile cannot
contain both a shared key and a legacy password.

New profiles use encryption, all IPv4 traffic, custom DNS `1.1.1.1`, DNS transport
(raw UDP disabled), lazy mode, a one-second timeout and IPv4 resolver transport.
Server proxy starts disabled. Advanced transport, DNS and route controls live
inside each profile editor, rather than the system Settings app. DNS may use the
system resolver, the tunnel server, or a custom IPv4 address. Subnet-only routing
also includes an explicit route for a configured tunnel/custom DNS address.

An existing single configuration is migrated once into the **Default** profile,
preserving its transport, DNS and routing behavior. Old HTTP/PAC settings are
retained for compatibility. Profile metadata and selection are stored together
in an atomic JSON file in Application Support. Each credential revision is a
separate Keychain item in the app/extension shared access group, available after
first device unlock. The app writes credentials before committing metadata;
failed credential writes leave the previous configuration intact. Plaintext
legacy passwords in preferences are removed only after migration succeeds.
Secrets never enter profile metadata, VPN options, logs or the app bundle.

The VPN manager stores the selected profile ID, credential revision and public
settings, so system-initiated reconnects use that same profile. Missing credentials,
a stale revision or a mode mismatch stop the connection without falling back to
another profile. Deleting a profile removes its credential item. Saving a profile
retires its previous revision; the app updates the disconnected VPN configuration
before it can reconnect.

Packets cross the Swift/C boundary as datagrams. The tunnel carries IPv4 only;
IPv6 is captured and discarded. The IPv6 resolver option controls only the outer
DNS transport. Sleep does not deliberately tear down the tunnel; normal transport
inactivity and network changes can still interrupt it. See
[protocol security](doc/security.md) for protocol properties and limits.

The native protocol tests cover encrypted and legacy DNS/raw UDP communication,
rotation, wrong credentials and downgrade rejection. An unsigned app build is
compile/link validation only, not an end-to-end iPhone VPN test.

## Server proxy mode

Enable **Server proxy** inside the selected profile before connecting. This requires
a shared key, protocol `0x602`, and an iodined server started with
`-X /absolute/path/to/manager.py` (see [companion server setup](doc/proxy-server.md)).
TCP and UDP, including DNS, are captured as IPv4 packets and encrypted by iodine.
The server converts these packets through an isolated SOCKS5 gateway; it also
provides authenticated HTTP/CONNECT and SOCKS5 endpoints for that session.
No iOS proxy credentials or extra libraries need to be configured. Proxy mode
forces the full IPv4 route and DNS `1.1.1.1`, unless the profile explicitly selects
a custom DNS server. Migrated manual PAC and HTTP proxy options are ignored in
this mode. Changes apply at reconnection.

If negotiation fails, the VPN does not start. A server gateway failure drops
traffic instead of reverting to ordinary server routing. IPv6 remains blocked;
ICMP and other non-TCP/UDP protocols are not relayed by SOCKS5. iOS system traffic
exempted from packet tunnels remains subject to Apple's routing policy. This is
not an always-on, supervised-device VPN policy; disconnecting restores normal
network access. A signed device test is required to validate actual iOS routing.

## Fork changes and validation

This fork adds encrypted 0x602 sessions with automatic traffic-key rotation,
explicit legacy mode, shared Keychain credentials, full IPv4 server proxy mode
for TCP/UDP/DNS, the UIKit scene lifecycle required by the current SDK, and multiple named profiles
with revision-scoped credentials and per-profile advanced settings.
The bundled client engine includes its upstream license and provenance.

Earlier engine validation included device Release and signed Debug builds, app
installation and launch on an iPhone, 20 native protocol/proxy tests (also with
ASan/UBSan), and live Internet TCP/DNS/UDP checks through the matching server.
Those live tunnel checks used the native client and do not establish a complete
iPhone traffic-routing test. The current profile refactor has separate device
and simulator build checks, plus the regression checks below; it has not been
installed or tested on a physical iPhone in this iteration. Signing identities,
profiles, server keys, user settings and build products are not part of the repository.

### Profile regression tests

Run the executable Swift checks on macOS with full Xcode installed:

```sh
./Tests/run-profile-tests.sh
```

These use an isolated preferences suite, temporary metadata files and a fake
credential vault. They cover profile selection/deletion, credential isolation,
secret-free metadata/options, mode and revision mismatch rejection, legacy and
encrypted migration, migration retry after vault failure, failed credential and
metadata writes, corrupt metadata preservation, validation
and canonical Android/iOS defaults. They do not replace signed-device checks of
shared Keychain entitlements or Network Extension routing.

### iOS interface smoke test

Validated on 2026-10-13: the complete profile UI scenario passed on the iPhone
18 Pro simulator (iOS 27) with real Keychain storage and four screenshot attachments.

Use an empty, dedicated Apple Silicon simulator with a recent iOS runtime. The
UI test creates two synthetic profiles, verifies encrypted-key validation and
independent legacy/encrypted settings, relaunches the app, and exercises editing,
Cancel, selection and deletion. Successful runs remove their synthetic profiles.
They never connect to a server or use a real server key. Screenshots are attached
to the Xcode result bundle.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./build-openssl.sh iphonesimulator
xcrun simctl list devices available
# Replace SIMULATOR_UDID with the dedicated simulator's identifier.
xcodebuild test -project PurpleHaze.xcodeproj -scheme 'Purple Haze' \
  -destination 'id=SIMULATOR_UDID' \
  -derivedDataPath build-ios/UI-DerivedData \
  -resultBundlePath build-ios/UI-Results.xcresult \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO
xcrun xcresulttool export attachments --path build-ios/UI-Results.xcresult \
  --output-path build-ios/UI-Screenshots
```

Ad-hoc simulator signing is required to exercise the real Keychain access group;
an unsigned simulator app fails with Keychain error `-34018`. The test dismisses
only the simulator's known Network Extension `IPC failed` startup alert and the
first-use keyboard introduction. This does not bypass credentials or simulate a
VPN connection. Device signing, VPN consent, system Settings reconnection and
real iPhone traffic routing still need a physical-device check.
