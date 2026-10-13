# Bundled iodine client sources

Upstream: https://github.com/yarrick/iodine
Base commit: `ea8b44a86e9b3ccc0889fcb06bd696059f541318`.

This snapshot contains the client C files and headers used by PurpleHaze, with
local changes for encrypted protocol 0x602, TLS 1.3 authentication, automatic
traffic-key rotation, explicit legacy 0x502 mode and server-proxy negotiation.
It is not a pristine upstream release. The iOS configuration and TUN bridge are
in the repository's `Extension/` directory. Original source notices and the iodine license are preserved.

The matching modified iodined server is maintained separately. Stock upstream
servers support only the legacy mode. Updating this snapshot requires reviewing
and testing the protocol changes in both the app and the companion server.
