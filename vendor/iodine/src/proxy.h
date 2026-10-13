/* Optional, isolated server-side HTTP/CONNECT/SOCKS5 gateway. */
#ifndef IODINE_PROXY_H
#define IODINE_PROXY_H
#include "common.h"
#include "run_as.h"
#define PROXY_USERS 16
#define PROXY_SECRET_LEN 32
struct proxy_peer {
    uint32_t generation;
    int status; /* 0 disabled, 1 starting, 2 ready, -1 failed (never bypass) */
    unsigned char services[4 + PROXY_SECRET_LEN]; /* HTTP/SOCKS ports, ASCII secret */
};
extern struct proxy_peer proxy_peers[PROXY_USERS];
int proxy_start(const char *, struct run_as_user *);
void proxy_stop(void);
int proxy_fd(void);
void proxy_user_stop(unsigned);
int proxy_user_start(unsigned, in_addr_t, in_addr_t, unsigned);
void proxy_send(unsigned, const void *, size_t);
/* Return a user id and IP packet, or -1 (including internal lifecycle replies). */
int proxy_receive(void *, size_t, int *);
#endif
