# Shared iodine client engine

Both PurpleHaze apps compile this **single canonical source tree**. There are no
platform copies or generated vendoring steps. Android uses `android/jni/Android.mk`;
iOS uses `ios/PurpleHaze.xcodeproj` and `ios/Build.xcconfig`. Both resolve headers
from this directory and their own platform configuration directory. OpenSSL is
built separately for each platform, using the same pinned 3.5.9 release.

Upstream: <https://github.com/yarrick/iodine>, base commit
`ea8b44a86e9b3ccc0889fcb06bd696059f541318`.
The engine includes local protocol changes: encrypted `0x602`, TLS 1.3 PSK-DHE
authentication, automatic traffic-key rotation, explicit legacy `0x502` mode and
authenticated server-proxy negotiation. This is not a pristine upstream release.
Only client source files and headers are included; the matching modified iodined
server and command-line programs are maintained separately.

The mobile snapshots came from the PurpleHaze iOS fork (original
DullJZ/PurpleHaze base `c310fd540c8fc05adb12c0e42023aedd930e9037`) and the Android
fork (original AndIodine base `82fcf7ba697c9b8d562e2bf4b6d5ded4c606da9d`).
Their complete Git histories remain in the monorepo merge ancestry. Protocol and
crypto code matched before consolidation. The following small adaptations were
reconciled so both platforms can use exactly the same engine:

- `client.c` uses the Android snapshot's C11 atomic cancellation flag and returns
  transport/TUN failures to the embedding app instead of terminating its process.
- `common.c` reports socket, bind and descriptor-flag failures without exiting the
  app; socket creation/bind errors return `-1` and close failed descriptors.
- `common.h` redirects diagnostics only when `IODINE_ANDROID_APP` is defined.
  Android supplies `android-log.h`; iOS keeps its existing stderr/log bridge.
- `tun.h` includes the Android `tun_getname` declaration. TUN implementations
  remain platform-specific. `util.c` is compiled by iOS only.
- Trailing blank-line differences were normalized; protocol behavior was not
  otherwise changed during the merge.

Platform adapters stay outside this directory:

- `android/jni/config.h`, `iodine-client.c`, `android-tun.[ch]`, `android-log.[ch]`;
- `ios/Extension/config.h`, `tun-shim.c`, `Iodine.swift` and its Swift/C bridge.

No server key, password or other user credential is bundled. The ISC iodine
license is in `LICENSE`; original source notices, including the MD5 license,
remain in the files. App-level licenses and third-party notices remain under
`android/` and `ios/`.

## Verification and updates

From the monorepo root, run:

```sh
python3 scripts/verify-vendor.py
```

The manifest covers all canonical C/header files and the iodine license. The
check also rejects reintroduced platform copies. After an intentional, reviewed
engine update, regenerate the manifest with:

```sh
python3 scripts/verify-vendor.py --update
```

An engine update must be built and tested for both mobile platforms. Changes to
the encrypted wire protocol also require tests against the matching server;
stock upstream servers support only legacy mode. Do not copy files into the old
`ios/vendor/iodine` or `android/jni/iodine` paths.
