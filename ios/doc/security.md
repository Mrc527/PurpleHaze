# Encrypted iodine protocol (0x00000602)

Encrypted sessions require a shared, randomly generated 32-byte **binary** key
file and OpenSSL 3.0 or newer (use a supported, patched release). A client with
`-K` selects protocol `0x602` and never falls back to plaintext, including on
key errors, handshake failure, or unavailable raw UDP. Upgrade the server
before connecting encrypted clients.

Without `-K`, the client selects unencrypted legacy protocol `0x502` directly.
It authenticates with `-P password`, `IODINE_PASS`, or an interactive password
prompt, and uses historical zlib packet framing over DNS and raw UDP. `-K` and
`-P` are mutually exclusive; `IODINE_PASS` is ignored when `-K` is supplied.
This is an explicit startup choice, not an automatic downgrade after failure.

The server also accepts encrypted `0x601` clients with the same key and wire
format. Its authenticated configuration echoes the client's negotiated version.
The initial experimental `0x600` format is not supported.

For migration, the server can additionally accept historical `0x502` clients
(including iodine 0.7/0.8) when explicitly configured with `-P password` or
`IODINED_PASS`. These credentials enable **unencrypted legacy traffic**, using
the historical password challenge and zlib framing. `-K keyfile` and legacy
credentials can coexist on the same listener; without legacy credentials,
`0x502` is rejected. A legacy-only server can omit `-K`. Interactive server
password prompts are not supported. Existing client addresses and DNS/raw UDP
transports remain supported, within the server's 1200-byte MTU ceiling.

Legacy traffic does not acquire the security properties described below.
The server translates packet formats when forwarding between old and new
clients, so the legacy leg remains unencrypted. Remove the legacy credentials
after migrating all clients. Passwords are never converted into encryption keys.

## Running it

Generate the key once, with private file permissions:

```sh
umask 077
openssl rand -out iodine.key 32
```

Transfer that file to the other endpoint over an authenticated, confidential
channel such as an existing SSH connection. Do not generate two independent
keys. Keep the file accessible only to the account starting iodine.

```sh
# Server
sudo ./build/iodined -f -K /absolute/path/iodine.key 10.0.0.1 t1.example.com
# Client (add -d utun on macOS as appropriate for your setup)
sudo ./build/iodine -f -K /absolute/path/iodine.key t1.example.com
```

For a direct LAN test, use `test.com` on both ends and specify the server's LAN
address before the client's domain. `-r` forces DNS transport; without it the
client may select encrypted raw UDP. IP forwarding, routes and firewall rules
are still configured separately. The server accepts MTUs from 68 through 1200;
the default is 1130. Very short query limits or long domains may require a lower
MTU so each encrypted packet fits within iodine's 16-fragment limit. A hostname
must also have room for the 38-byte secure login request after Base32 encoding.

Traffic keys rotate automatically in each direction on the next outgoing record
after one hour, or after 2^20 records under one key. **Key rotation does not
disconnect the tunnel or require restarting the client.** The tunnel address
and application connections remain unchanged. A transport change between DNS
and raw UDP uses the same key epochs and counters. Normal transport inactivity
timeouts still apply; sessions no longer expire merely because of their age.

## Security properties and limits

- TLS 1.3 external PSK authentication, restricted to X25519 key exchange and
  `TLS_CHACHA20_POLY1305_SHA256`. PSK-only key exchange, TLS 1.2, early data and
  session tickets are not enabled. The code checks that a PSK and an ephemeral
  key exchange were actually negotiated.
- IP packets use ChaCha20-Poly1305 with distinct sending and receiving keys,
  derived with the standard TLS exporter. Modification, reflection, use in a
  different session, and record-type substitution fail authentication.
- A 64-record receive window per key epoch rejects replays while permitting
  bounded packet reordering. The previous epoch remains acceptable for 60 seconds
  after a successful key transition. Keys and replay windows advance only after
  successful authentication. DNS retransmissions reuse the original ciphertext,
  without encrypting again.
- Assigned IP addresses, netmask, MTU, protocol version and user ID are sent as
  authenticated TLS application data before the client configures its interface.
- Compression is disabled. It must not be reintroduced before encryption
  without addressing compression-related information leakage.
- Clients may send IPv4 packets only from their assigned tunnel address. Routing
  a subnet behind a client is not supported by this source-address policy.
- The server decrypts client-to-client traffic and encrypts it with the
  recipient's session. This is protection between each client and the server,
  not end-to-end encryption between clients.

The shared key defines one trust group: every holder can authenticate as a
client **or as the server**. This does not provide individual peer identities,
per-client revocation, or protection from another holder impersonating a peer.
Compromise of the long-term key alone does not reveal recorded sessions after
TLS's ephemeral secrets and the relevant session keys have been erased.
Compromise of an endpoint or its live session memory is outside this guarantee.
Automatic key rotation uses a one-way HKDF traffic-secret chain. It erases old
secrets, but does not perform a new Diffie-Hellman exchange: possession of a live
traffic secret allows deriving subsequent keys in that direction. Rotation does
not provide recovery from such a compromise; a new authenticated handshake is
needed after securing the affected endpoint. TLS/exporter state is discarded
after the initial configuration exchange.

DNS names, transport headers, packet sizes, timing, probes, ACKs and codec
negotiation remain visible. DNS control/framing messages are not authenticated;
an attacker can alter these to interrupt or degrade the transport or occupy
user slots. Such manipulation must never result in accepting unauthenticated
IP traffic. Raw login and keepalives are authenticated. This does not prevent
blocking, DNS filtering, traffic analysis, or denial of service.

This is a new iodine-specific integration of established primitives, not an
audited VPN implementation. The local tests cover cryptographic rejection and
protocol operation; an independent security review is still required before
claiming security equivalent to an established VPN.

## Wire format

Version negotiation retains iodine's existing framing, with version
`0x00000602`; its nonce is not an authentication mechanism. It allocates a user
slot, initially unauthenticated. Login (`L`) then carries a TLS byte stream:

```
request:  user_id:u8 | cache_miss:u16 | exchange:u16be | length:u8 | TLS bytes
response: exchange:u16be | length:u8 | TLS bytes
```

Each exchange carries at most 32 TLS bytes in each direction. Empty requests
poll pending server output. The client sends one exchange at a time and retries
it on loss; the server caches the previous request and response and never feeds
a retransmission into TLS twice. The cache-miss field is outside that request
cache and changes on retries. Out-of-order or conflicting requests are rejected.
An exchange sequence has a maximum of 512 steps and no wraparound. TLS input is
bounded, and unauthenticated login exchanges do not extend the initial 60-second
user-slot timeout. TLS records authenticate the reassembled handshake stream.

After TLS completes, the server writes this single TLS application record:

```
602 <user_id_decimal> <server_ipv4> <client_ipv4> <mtu_decimal> <prefix_decimal>
```

For a `0x601` client, the first field is `601`. The client validates it against
the version it requested before configuring the TUN. The exporter label is
`EXPORTER-iodine-v6.1-datagram`, without exporter context, and produces 64 bytes:

| Bytes | Meaning |
| --- | --- |
| 0–31 | Initial client-to-server traffic secret |
| 32–63 | Initial server-to-client traffic secret |

Each direction starts at epoch zero. HKDF-Expand with SHA-256, the traffic secret
as its input key and the ASCII info `iodine-v6.1 key/iv` produces 44 bytes: a
32-byte ChaCha20-Poly1305 key followed by a 12-byte base IV. To advance an epoch,
HKDF-Expand with info `iodine-v6.1 update` produces the next 32-byte traffic
secret. Info strings exclude their terminating NUL. The sender erases the old
secret and keys, increments the epoch, and resets the counter to zero.

Protected datagrams are `epoch:u32be | counter:u64be | ciphertext | tag:16`.
The nonce is the 12-byte directional base IV XOR the counter left-padded to 12
bytes. Associated data is `record_type:u8 | epoch:u32be | counter:u64be`. Types
are 1 for IP data, 2 for raw login and 3 for raw keepalive. Each direction uses
one counter across all types within an epoch; raw login and keepalive have empty
plaintext. The receiver can derive up to four epochs ahead to tolerate loss,
but commits that transition only after authenticating the packet. Larger jumps
are rejected to bound work on untrusted input. Only the immediately previous
epoch's receive key and replay window are retained for late packets, for up to
60 seconds; its derivation secret is erased immediately. Expired previous keys
are erased on the next send or receive. Neither epoch nor counter may wrap.

An IP plaintext is iodine's four-byte TUN prefix followed by the complete IPv4
packet. Overhead is 28 bytes per packet, plus existing iodine framing. Encryption happens before DNS
fragmentation; authentication happens after reassembly and before IP parsing
or TUN delivery. The old downstream compression flag bit is reserved.

## Build and validation

Meson requires OpenSSL and zlib (for legacy protocol support);
there is no build option that removes encryption.
OpenBSD uses the `eopenssl35` pkg-config package to avoid the base LibreSSL.
Windows and Android link OpenSSL statically, so its security fixes require
rebuilding iodine. Cross builds must provide target OpenSSL headers/libraries
and a target-only `PKG_CONFIG_LIBDIR`; the CI workflows show the complete setup.

`meson test -C build --print-errorlogs` always runs the standalone security tests.
On native Unix builds it also runs real client/server DNS and raw UDP handlers
on loopback, replacing only privileged TUN access with socketpairs. These tests
cover every supported DNS query type, small and fragmented packets, both
directions, forwarding between clients with different transports, and rejection
of forged source addresses. A virtual crypto clock crosses the former one-hour
deadline on every outgoing IP packet in these transport tests. Unit tests also
simulate over 100 hours of bidirectional use, counter-triggered rotation, lost
epochs, delayed packets, replay rejection across rotations and key erasure.
The transport tests need permission to bind loopback UDP sockets.
The remaining historical suites require libcheck.
Compatibility tests exercise both encrypted protocol versions and an independent
`0x502` DNS/raw UDP client, the native client in legacy mode across every DNS
query type and raw UDP, wrong-password rejection, explicit legacy enablement,
fragmented packets and forwarding between encrypted and legacy clients.

For a live-server check without changing local routes or requiring a local TUN,
run `python3 tests/live_tunnel.py build/test_secure_client KEY SERVER_IP DOMAIN`.
Append `raw` to check direct UDP. The helper uses the real client code and sends
ICMP echo requests through the remote server's TUN; only the local TUN is replaced
by a socketpair. Its virtual crypto clock also forces key rotation between packets.

References: [TLS 1.3](https://www.rfc-editor.org/rfc/rfc8446),
[OpenSSL TLS exporters](https://docs.openssl.org/3.0/man3/SSL_export_keying_material/),
[OpenSSL HKDF](https://docs.openssl.org/3.0/man3/EVP_PKEY_CTX_set_hkdf_md/),
[ChaCha20-Poly1305](https://www.rfc-editor.org/rfc/rfc8439),
[compression attacks](https://community.openvpn.net/Security%20Announcements/VORACLE).


## Optional proxy capability

Protocol `0x602` optionally negotiates a server proxy via DNS command `G` after
TLS login. Record kinds 4 and 5 authenticate the request and reply separately;
replies echo a fresh request nonce. `-X` requires `-K` on the CLI and never
falls back when unsupported. Existing `0x602`, encrypted `0x601` and explicitly
enabled legacy `0x502` clients retain their previous behavior without this flag.

Requested IPv4 TCP/UDP traffic (including DNS) is converted on the server through
an isolated HEV/3proxy pair. Each session has independent random credentials,
listeners, generation-tagged private IPC and bounded connection counts. Worker
failure keeps that session blocked rather than returning it to ordinary TUN
forwarding. Traffic to the server's own tunnel address is still delivered to its
TUN. ICMP/IPv6 are not Internet proxy transports. The helpers run outside the
optional server chroot with the selected unprivileged UID; process separation is
not a container or destination firewall. See [proxy setup](proxy-server.md)
for dependencies, route configuration, endpoint authorization and lifecycle.
