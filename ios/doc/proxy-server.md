# Companion server setup

These instructions apply to the modified **iodine server repository**, which is
maintained separately. This PurpleHaze fork bundles only the client engine.

# Optional server proxy gateway

Build iodine normally, then build the pinned server helpers (Linux or macOS):

```sh
./tools/proxy/build.sh
```

Requires a C compiler, make, git, and Python 3.9 or newer at runtime. The build
fetches HEV socks5-tunnel and 3proxy at the exact commits in `build.sh`, including
HEV's submodules. Copy **all of `build-proxy/bin/`**, including `licenses/`, to a
root-owned, non-user-writable installation directory such as
`/usr/local/libexec/iodine-proxy/`. Do not install just `manager.py`.

Start the server with an absolute executable path:

```sh
sudo iodined -f -u iodine -K /etc/iodine/secure.key \
  -X /usr/local/libexec/iodine-proxy/manager.py 10.11.12.1/27 i.example.com
```

The supervisor starts before the optional `-t` chroot, with the user selected by
`-u`. Python and the helper binaries therefore belong on the host filesystem,
not in the chroot. The supervisor inherits only a private control socket (fd 3)
and standard streams. No public control socket or kernel forwarding/NAT is needed.
Use a dedicated unprivileged account and normal host egress firewall policy.
The gateway can access destinations reachable by that account, including private
networks and loopback services; it is not a destination-isolation firewall.

The CLI requests this mode with **`-X`**, together with **`-K`**:

```sh
sudo iodine -f -r -K ./iodine.key -X RESOLVER_IP i.example.com
```

`-X` enables the server gateway for packets sent into iodine's TUN. As with normal
iodine, the CLI **does not change the host's default route or DNS configuration**.
Configure IPv4 routes and DNS to use the tunnel, preserving a route to the outer
DNS resolver/server via the physical interface. Block IPv6 if configuring full
host tunneling. These OS-specific changes require administrative privileges.
PurpleHaze's **Proxy TCP / UDP / DNS** switch sets up the device's packet tunnel
routes and tunneled DNS automatically; it captures and drops IPv6.

TCP and UDP, including DNS, are converted from IP to SOCKS5 on the server. This
keeps every inner flow inside iodine's encrypted channel until it reaches the
server, without needing tun2socks inside the iOS Network Extension. External
HTTPS connections retain their application TLS encryption. Plain HTTP receives
only iodine's client-to-server protection, not encryption beyond the server.
ICMP and other non-TCP/UDP protocols are not relayed by SOCKS5. Traffic to the
server's own tunnel IP continues through its TUN, to reach the proxy endpoints
and other services on that host.

Each authenticated `0x602` session requesting the feature receives:

- a separate HEV TCP/IP stack and 3proxy process, with 128-session limits;
- an internal SOCKS5 listener on loopback;
- HTTP/CONNECT and SOCKS5 listeners bound only to the server's tunnel IPv4,
  restricted to that client's assigned source IP;
- a random 128-bit session password (32 hexadecimal characters), username
  `iodine`, and dynamically allocated HTTP/SOCKS ports.

The password travels only over private IPC and the authenticated encrypted
control exchange. It is not in process arguments, config files or logs. Ports
are logged. The client embedding API exposes ports and password through
`client_get_proxy_http_port()`, `client_get_proxy_socks_port()` and
`client_get_proxy_password()`; automatic mode does not require entering these.

The `G` capability exchange uses authenticated record types 4/5 and binds each
response to the request nonce. It is optional within `0x602`: existing `0x602`
clients, encrypted `0x601` clients and opt-in plaintext `0x502` clients retain
normal tunnel behavior. Plaintext and `0x601` sessions cannot request the proxy.
A client requesting `-X` fails if the server does not support or enable it.
There is no silent fallback to ordinary server forwarding. A worker failure
revokes the proxy session; traffic stays blocked until a fresh tunnel login.
Session expiry/reuse closes listeners and discards credentials. There is no
new one-hour lifetime or forced periodic reconnection.

The backend processes are outside iodined's chroot, isolated per session but
not containers or a security sandbox. Keep the pinned dependencies updated as
part of normal server maintenance. Server proxies are currently Unix-only.

## Verification

```sh
meson test -C build --print-errorlogs
python3 tests/proxy_backend.py build-proxy/bin/manager.py
python3 tests/proxy_tunnel.py build/test_secure_server build/test_secure_client build-proxy/bin/manager.py
```

The first proxy test exercises HTTP, CONNECT, SOCKS5 TCP/UDP, credentials and
revocation. The second injects independent IPv4/TCP/UDP packets through real C
client/server processes over encrypted DNS and raw UDP. It checks that replies
return through the tunnel and no proxied traffic reaches the fake server TUN.
Tests need permission to open local sockets, but no root/TUN configuration.
An unsigned iOS build only verifies compilation; actual iPhone routing still
requires a signed device test.
