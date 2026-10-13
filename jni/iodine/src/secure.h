/* Authenticated tunnel sessions. See doc/security.md for the wire format. */
#ifndef IODINE_SECURE_H
#define IODINE_SECURE_H

#include <stddef.h>
#include <stdint.h>

#define SECURE_KEY_LEN 32
#define SECURE_OVERHEAD 28
#define SECURE_CHUNK 32
#define SECURE_RPC_MAX 512
#define SECURE_DATA 1
#define SECURE_RAW_LOGIN 2
#define SECURE_PING 3
#define SECURE_CONTROL_REQUEST 4
#define SECURE_CONTROL_REPLY 5

struct secure_session;
int secure_valid_packet(const void *, size_t);
int secure_load_key(const char *, unsigned char [SECURE_KEY_LEN]);
struct secure_session *secure_new(const unsigned char *, int);
void secure_free(struct secure_session *);
int secure_ready(const struct secure_session *);
int secure_handshake(struct secure_session *, const void *, size_t);
int secure_drain(struct secure_session *, void *, size_t);
int secure_read_config(struct secure_session *, void *, size_t);
int secure_server_exchange(struct secure_session *, const void *, size_t,
    void *, const void *, size_t);
int secure_seal(struct secure_session *, unsigned char, const void *, size_t,
    void *, size_t);
int secure_open(struct secure_session *, unsigned char, const void *, size_t,
    void *, size_t);

#endif
