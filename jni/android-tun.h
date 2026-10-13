#ifndef IODINE_ANDROID_TUN_H
#define IODINE_ANDROID_TUN_H
struct android_tun_config { char ip[16], peer[16]; int netbits, mtu; };
extern struct android_tun_config android_tun;
#endif
