# Bundled iodine client

Imported from Marco's iodine working tree, based on yarrick/iodine commit
`ea8b44a`, including the local encrypted 0x602 protocol, rekeying and authenticated
server-proxy negotiation. This app is self-contained; no sibling checkout is
needed to build it. The upstream AndIodine base is
`82fcf7ba697c9b8d562e2bf4b6d5ded4c606da9d` (2024-09-03).

Android adapter changes to the imported core:

* `client.c`: atomic cancellation flag; fatal CLI exits return failures to JNI.
* `common.c`: socket/fcntl failures are returned/logged instead of exiting the app.
* `common.h`: redirect diagnostic output to the Android log/foreground UI adapter.
* `../android-tun.c`: VpnService supplies the raw-IP file descriptor; convert
  between raw IPv4 packets and iodine's four-byte internal prefix. Reject IPv6.
* `../iodine-client.c`: separate configuration/socket creation from handshake so
  Java protects and binds the transport socket before any VPN route is installed.

Only the worker owns native cleanup and socket closure. Java owns the TUN
ParcelFileDescriptor, avoiding the upstream double-close. Encrypted connections
never fall back to plaintext; proxy mode requires a key and successful server
capability negotiation. No shared server key is bundled.
