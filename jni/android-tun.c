/* ISC license; see iodine/LICENSE. VpnService owns the raw-IP TUN descriptor. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include "iodine/src/tun.h"
#include "android-tun.h"
struct android_tun_config android_tun;
int open_tun(const char *name) { (void)name; return -1; }
void close_tun(int fd) { (void)fd; /* Java ParcelFileDescriptor owns it. */ }
const char *tun_getname(void) { return "Android VPN"; }
int tun_setip(const char *ip, const char *peer, int netbits) {
    struct in_addr a;
    if (netbits < 1 || netbits > 32 || inet_pton(AF_INET, ip, &a) != 1 ||
        inet_pton(AF_INET, peer, &a) != 1) return -1;
    snprintf(android_tun.ip, sizeof(android_tun.ip), "%s", ip);
    snprintf(android_tun.peer, sizeof(android_tun.peer), "%s", peer);
    android_tun.netbits = netbits;
    return 0;
}
int tun_setmtu(unsigned mtu) {
    if (mtu < 576 || mtu > 1500) return -1;
    android_tun.mtu = (int)mtu;
    return 0;
}
ssize_t read_tun(int fd, char *buf, size_t len) {
    if (len <= 4) return -1;
    ssize_t n = read(fd, buf + 4, len - 4);
    if (n <= 0) return n;
    if (((unsigned char)buf[4] >> 4) != 4) return 0;
    memset(buf, 0, 4);
    return n + 4;
}
int write_tun(int fd, char *buf, size_t len) {
    if (len <= 4 || ((unsigned char)buf[4] >> 4) != 4) return -1;
    return write(fd, buf + 4, len - 4) == (ssize_t)(len - 4) ? 0 : -1;
}
