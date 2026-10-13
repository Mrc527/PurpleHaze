# PurpleHaze for encrypted iodine

Based on [DullJZ/PurpleHaze](https://github.com/DullJZ/PurpleHaze), commit
`c310fd540c8fc05adb12c0e42023aedd930e9037` (Apache-2.0, derived from osy/PurpleHaze).
The Xcode project builds the modified iodine client bundled in `vendor/iodine/src`.
No sibling checkout or Git submodule is required. Original app attribution and
licenses are preserved in `LICENSE` and the bundled `ThirdPartyNotices.txt`.

Requires a Mac with full Xcode, iOS SDK, and iOS 15 or later on an arm64 iPhone
or iPad. OpenSSL 3.5.9 is linked statically. Rebuild the app when updating it.

## Build

Clone this fork and enter its directory:

```sh
git clone https://github.com/Mrc527/PurpleHaze.git
cd PurpleHaze
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

Enter the delegated top domain. Advanced Settings contains the resolver address,
DNS type and raw UDP toggle. For encrypted mode, paste the Base64 representation
of the server's existing **32-byte binary key** into **Shared key**. Convert the
file locally with `openssl base64 -A -in /path/to/iodine.key` and transfer it over
a trusted channel. Do not generate a different key for this client.

With a key, the client requests `0x602`, with TLS authentication, encrypted packets
and automatic traffic-key rotation. An invalid key or failed handshake never
falls back to plaintext. The legacy password field is ignored in encrypted mode.

Leave Shared key empty to use **unencrypted `0x502`**, and enter the server's
legacy password (at most 32 UTF-8 bytes). The server must allow legacy sessions.
This matches the command-line client's behavior without `-K`.

Secrets are stored in a shared Keychain group, accessible after first unlock on
that device, and are excluded from UserDefaults, VPN options, logs and bundles.
The persisted mode flag prevents a missing encrypted credential from silently
selecting plaintext. Packets cross the Swift/C boundary as datagrams. The tunnel
carries IPv4 only; IPv6 is captured and discarded. Sleep does not deliberately
tear down the tunnel; normal transport inactivity and network changes can still
interrupt it. See [protocol security](doc/security.md) for protocol properties and limits.

The native protocol tests cover encrypted and legacy DNS/raw UDP communication,
rotation, wrong credentials and downgrade rejection. An unsigned app build is
compile/link validation only, not an end-to-end iPhone VPN test.

## Server proxy mode

Enable **Proxy TCP / UDP / DNS** on the main screen before connecting. This requires
a shared key, protocol `0x602`, and an iodined server started with
`-X /absolute/path/to/manager.py` (see [companion server setup](doc/proxy-server.md)).
TCP and UDP, including DNS, are captured as IPv4 packets and encrypted by iodine.
The server converts these packets through an isolated SOCKS5 gateway; it also
provides authenticated HTTP/CONNECT and SOCKS5 endpoints for that session.
No iOS proxy credentials or extra libraries need to be configured. Manual PAC and
HTTP proxy preferences are ignored in this mode. Changes apply at reconnection.

If negotiation fails, the VPN does not start. A server gateway failure drops
traffic instead of reverting to ordinary server routing. IPv6 remains blocked;
ICMP and other non-TCP/UDP protocols are not relayed by SOCKS5. iOS system traffic
exempted from packet tunnels remains subject to Apple's routing policy. This is
not an always-on, supervised-device VPN policy; disconnecting restores normal
network access. A signed device test is required to validate actual iOS routing.

## Fork changes and validation

This fork adds encrypted 0x602 sessions with automatic traffic-key rotation,
explicit legacy mode, shared Keychain credentials, full IPv4 server proxy mode
for TCP/UDP/DNS, and the UIKit scene lifecycle required by the current SDK.
The bundled client engine includes its upstream license and provenance.

Validation performed: device Release and signed Debug builds, successful app
installation and launch on an iPhone, 20 native protocol/proxy tests (also with
ASan/UBSan), and live Internet TCP/DNS/UDP checks through the matching server.
The live tunnel checks used the native client; they do not establish a complete
iPhone traffic-routing test. Signing identities, profiles, server keys, user
settings and build products are not part of the repository.
