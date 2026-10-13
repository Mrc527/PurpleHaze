/* TLS 1.3 PSK-DHE authentication and exporter-bound datagram protection. */
#include "secure.h"
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <limits.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/crypto.h>
#include <openssl/kdf.h>

/* Overridden only by tests that compile this file with a virtual clock. */
#ifndef SECURE_NOW
#define SECURE_NOW() time(NULL)
#endif

#define REKEY_SECONDS 3600
#define REKEY_RECORDS (UINT64_C(1) << 20)
#define REKEY_MAX_SKIP 4
#define REKEY_GRACE_SECONDS 60

struct secure_epoch {
	unsigned char secret[32], key[32], iv[12];
	uint64_t sent, highest, seen;
	uint32_t number;
};

struct secure_session {
	SSL *tls;
	unsigned char psk[32];
	struct secure_epoch tx, rx, previous;
	time_t tx_started, previous_until;
	int have_previous;
	int server, ready, failed, config_sent;
	unsigned int exchange;
	unsigned char request[3 + SECURE_CHUNK], reply[3 + SECURE_CHUNK];
	size_t request_len, reply_len;
};

/* Domain-separated HKDF expansion, using OpenSSL's implementation. */
static int
expand(const unsigned char secret[32], const char *label, void *out, size_t len)
{
	EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_HKDF, NULL);
	int ok;
	if (!ctx) return 0;
	ok = EVP_PKEY_derive_init(ctx) > 0 &&
	    EVP_PKEY_CTX_set_hkdf_mode(ctx, EVP_PKEY_HKDEF_MODE_EXPAND_ONLY) > 0 &&
	    EVP_PKEY_CTX_set_hkdf_md(ctx, EVP_sha256()) > 0 &&
	    EVP_PKEY_CTX_set1_hkdf_key(ctx, secret, 32) > 0 &&
	    EVP_PKEY_CTX_add1_hkdf_info(ctx, (const unsigned char *)label, strlen(label)) > 0 &&
	    EVP_PKEY_derive(ctx, out, &len) > 0;
	EVP_PKEY_CTX_free(ctx);
	return ok;
}

static int
epoch_material(struct secure_epoch *epoch)
{
	unsigned char material[44];
	int ok = expand(epoch->secret, "iodine-v6.1 key/iv", material, sizeof(material));
	if (ok) {
		memcpy(epoch->key, material, 32);
		memcpy(epoch->iv, material + 32, 12);
	}
	OPENSSL_cleanse(material, sizeof(material));
	return ok;
}

static int
epoch_next(struct secure_epoch *epoch)
{
	struct secure_epoch next = {0};
	int ok = epoch->number != UINT32_MAX &&
	    expand(epoch->secret, "iodine-v6.1 update", next.secret, sizeof(next.secret)) &&
	    epoch_material(&next);
	if (ok) {
		next.number = epoch->number + 1;
		OPENSSL_cleanse(epoch, sizeof(*epoch));
		*epoch = next;
	}
	OPENSSL_cleanse(&next, sizeof(next));
	return ok;
}

static void
expire_previous(struct secure_session *s)
{
	if (s->have_previous && SECURE_NOW() >= s->previous_until) {
		OPENSSL_cleanse(&s->previous, sizeof(s->previous));
		s->have_previous = 0;
	}
}

int
secure_valid_packet(const void *data, size_t len)
{
	const unsigned char *p = data;
	size_t header, total;
	/* Iodine's portable TUN representation has a four-byte prefix. */
	if (len < 24 || len > 1204 || (p[4] >> 4) != 4) return 0;
	header = (p[4] & 15) * 4;
	total = ((size_t)p[6] << 8) | p[7];
	return header >= 20 && total >= header && total == len - 4;
}

int
secure_load_key(const char *path, unsigned char key[32])
{
	unsigned char buf[33];
	FILE *f;
	size_t n;
	int ok;
	memset(key, 0, 32);
	if (!path || !(f = fopen(path, "rb"))) return 0;
	n = fread(buf, 1, sizeof(buf), f);
	ok = n == 32 && !ferror(f);
	fclose(f);
	if (ok) memcpy(key, buf, 32);
	OPENSSL_cleanse(buf, sizeof(buf));
	return ok;
}

static SSL_SESSION *
psk_session(SSL *tls)
{
	static const unsigned char cipher_id[] = {0x13, 0x03};
	struct secure_session *s = SSL_get_app_data(tls);
	const SSL_CIPHER *cipher = SSL_CIPHER_find(tls, cipher_id);
	SSL_SESSION *session = SSL_SESSION_new();
	if (!session || !cipher ||
	    !SSL_SESSION_set1_master_key(session, s->psk, sizeof(s->psk)) ||
	    !SSL_SESSION_set_cipher(session, cipher) ||
	    !SSL_SESSION_set_protocol_version(session, TLS1_3_VERSION)) {
		SSL_SESSION_free(session);
		return NULL;
	}
	return session;
}

static int
client_psk(SSL *tls, const EVP_MD *md, const unsigned char **id,
    size_t *idlen, SSL_SESSION **session)
{
	static const unsigned char identity[] = "iodine-v6.1";
	if (md && EVP_MD_get_type(md) != NID_sha256) return 0;
	*id = identity;
	*idlen = sizeof(identity) - 1;
	*session = psk_session(tls);
	return *session != NULL;
}

static int
server_psk(SSL *tls, const unsigned char *id, size_t idlen,
    SSL_SESSION **session)
{
	*session = NULL;
	if (idlen != 11 || memcmp(id, "iodine-v6.1", 11)) return 0;
	*session = psk_session(tls);
	return *session != NULL;
}

struct secure_session *
secure_new(const unsigned char *key, int server)
{
	struct secure_session *s = OPENSSL_zalloc(sizeof(*s));
	SSL_CTX *ctx = SSL_CTX_new(TLS_method());
	BIO *in = NULL, *out = NULL;
	if (!s || !ctx) goto fail;
	memcpy(s->psk, key, 32);
	s->server = server;
	if (!SSL_CTX_set_min_proto_version(ctx, TLS1_3_VERSION) ||
	    !SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION) ||
	    !SSL_CTX_set_ciphersuites(ctx, "TLS_CHACHA20_POLY1305_SHA256") ||
	    !SSL_CTX_set1_groups_list(ctx, "X25519") ||
	    !SSL_CTX_set_num_tickets(ctx, 0)) goto fail;
	SSL_CTX_set_options(ctx, SSL_OP_NO_COMPRESSION | SSL_OP_NO_TICKET);
	SSL_CTX_clear_options(ctx, SSL_OP_ALLOW_NO_DHE_KEX);
	SSL_CTX_set_session_cache_mode(ctx, SSL_SESS_CACHE_OFF);
	SSL_CTX_set_psk_use_session_callback(ctx, client_psk);
	SSL_CTX_set_psk_find_session_callback(ctx, server_psk);
	s->tls = SSL_new(ctx);
	in = BIO_new(BIO_s_mem());
	out = BIO_new(BIO_s_mem());
	if (!s->tls || !in || !out) goto fail;
	BIO_set_mem_eof_return(in, -1);
	SSL_set_bio(s->tls, in, out);
	SSL_set_app_data(s->tls, s);
	if (server) SSL_set_accept_state(s->tls);
	else SSL_set_connect_state(s->tls);
	SSL_CTX_free(ctx);
	return s;
fail:
	BIO_free(in);
	BIO_free(out);
	SSL_CTX_free(ctx);
	secure_free(s);
	return NULL;
}

void
secure_free(struct secure_session *s)
{
	if (!s) return;
	SSL_free(s->tls);
	OPENSSL_clear_free(s, sizeof(*s));
}

int
secure_ready(const struct secure_session *s)
{
	return s && s->ready && !s->failed;
}

int
secure_handshake(struct secure_session *s, const void *data, size_t len)
{
	unsigned char keys[64];
	static const char label[] = "EXPORTER-iodine-v6.1-datagram";
	int r, error;
	if (!s || s->failed || len > SECURE_CHUNK) return -1;
	if (!s->tls) return s->ready && !len ? 1 : -1;
	ERR_clear_error();
	if (len && BIO_write(SSL_get_rbio(s->tls), data, (int)len) != (int)len)
		goto fail;
	if (BIO_ctrl_pending(SSL_get_rbio(s->tls)) > 16384) goto fail;
	if (s->ready) return 1;
	r = SSL_do_handshake(s->tls);
	if (r != 1) {
		error = SSL_get_error(s->tls, r);
		if (error == SSL_ERROR_WANT_READ) return 0;
		goto fail;
	}
	/* External PSK authentication is mandatory; never accept certificates
	 * without verification, or a PSK-only handshake without forward secrecy. */
	if (!SSL_session_reused(s->tls) || SSL_get_negotiated_group(s->tls) == 0 ||
	    !SSL_export_keying_material(s->tls, keys, sizeof(keys), label,
	    sizeof(label) - 1, NULL, 0, 0)) goto fail;
	memcpy(s->tx.secret, keys + (s->server ? 32 : 0), 32);
	memcpy(s->rx.secret, keys + (s->server ? 0 : 32), 32);
	if (!epoch_material(&s->tx) || !epoch_material(&s->rx)) goto fail;
	s->tx_started = SECURE_NOW();
	OPENSSL_cleanse(keys, sizeof(keys));
	OPENSSL_cleanse(s->psk, sizeof(s->psk));
	s->ready = 1;
	return 1;
fail:
	OPENSSL_cleanse(keys, sizeof(keys));
	s->failed = 1;
	return -1;
}

int
secure_drain(struct secure_session *s, void *out, size_t cap)
{
	if (!s || s->failed || cap > INT_MAX) return -1;
	if (!s->tls) return 0;
	if (!BIO_ctrl_pending(SSL_get_wbio(s->tls))) return 0;
	return BIO_read(SSL_get_wbio(s->tls), out, (int)cap);
}

int
secure_read_config(struct secure_session *s, void *out, size_t cap)
{
	int r;
	if (!secure_ready(s) || !s->tls || cap > INT_MAX) return -1;
	ERR_clear_error();
	r = SSL_read(s->tls, out, (int)cap);
	if (r > 0) {
		/* Discard TLS/exporter roots so retired traffic keys cannot be
		 * reconstructed from a retained handshake object. */
		SSL_free(s->tls);
		s->tls = NULL;
		return r;
	}
	if (SSL_get_error(s->tls, r) == SSL_ERROR_WANT_READ) return 0;
	s->failed = 1;
	return -1;
}

/* Reliable, bounded TLS stream over stop-and-wait DNS exchanges. Duplicate
 * requests return exactly the cached reply, without feeding TLS twice. */
int
secure_server_exchange(struct secure_session *s, const void *request, size_t len,
    void *reply, const void *config, size_t config_len)
{
	const unsigned char *p = request;
	unsigned int seq;
	int n;
	if (!s || s->failed || len < 3 || len > sizeof(s->request) ||
	    p[2] != len - 3 || config_len > 256) return -1;
	seq = ((unsigned int)p[0] << 8) | p[1];
	if (s->exchange && seq == s->exchange - 1) {
		if (len != s->request_len || memcmp(p, s->request, len)) return -1;
		memcpy(reply, s->reply, s->reply_len);
		return (int)s->reply_len;
	}
	if (seq != s->exchange || seq >= SECURE_RPC_MAX) return -1;
	if (secure_handshake(s, p + 3, len - 3) < 0) return -1;
	if (secure_ready(s) && !s->config_sent) {
		if (SSL_write(s->tls, config, (int)config_len) != (int)config_len) {
			s->failed = 1;
			return -1;
		}
		s->config_sent = 1;
	}
	n = secure_drain(s, s->reply + 3, SECURE_CHUNK);
	if (n < 0) return -1;
	s->reply[0] = p[0]; s->reply[1] = p[1]; s->reply[2] = n;
	s->reply_len = n + 3;
	memcpy(s->request, p, len);
	s->request_len = len;
	s->exchange++;
	if (s->tls && s->config_sent && !BIO_ctrl_pending(SSL_get_wbio(s->tls))) {
		SSL_free(s->tls);
		s->tls = NULL;
	}
	memcpy(reply, s->reply, s->reply_len);
	return (int)s->reply_len;
}

static void
nonce_for(unsigned char nonce[12], const unsigned char iv[12], const unsigned char *seq)
{
	int i;
	memcpy(nonce, iv, 12);
	for (i = 0; i < 8; i++) nonce[i + 4] ^= seq[i];
}

int
secure_seal(struct secure_session *s, unsigned char kind, const void *in, size_t len,
    void *out, size_t cap)
{
	unsigned char *p = out, nonce[12];
	EVP_CIPHER_CTX *ctx;
	uint64_t seq;
	time_t now;
	int n, tail, i, ok;
	if (!secure_ready(s) || len > 65535 || cap < len + SECURE_OVERHEAD) return -1;
	expire_previous(s);
	now = SECURE_NOW();
	if (s->tx.sent >= REKEY_RECORDS || difftime(now, s->tx_started) >= REKEY_SECONDS) {
		if (!epoch_next(&s->tx)) {
			s->failed = 1;
			return -1;
		}
		s->tx_started = now;
	}
	p[0] = s->tx.number >> 24; p[1] = s->tx.number >> 16;
	p[2] = s->tx.number >> 8; p[3] = s->tx.number;
	seq = s->tx.sent++;
	for (i = 11; i >= 4; i--) { p[i] = seq & 255; seq >>= 8; }
	nonce_for(nonce, s->tx.iv, p + 4);
	ctx = EVP_CIPHER_CTX_new();
	if (!ctx) return -1;
	ok = EVP_EncryptInit_ex(ctx, EVP_chacha20_poly1305(), NULL, s->tx.key, nonce) &&
	    EVP_EncryptUpdate(ctx, NULL, &n, &kind, 1) &&
	    EVP_EncryptUpdate(ctx, NULL, &n, p, 12) &&
	    EVP_EncryptUpdate(ctx, p + 12, &n, in, (int)len) &&
	    EVP_EncryptFinal_ex(ctx, p + 12 + len, &tail) &&
	    EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, 16, p + 12 + len);
	EVP_CIPHER_CTX_free(ctx);
	return ok ? (int)(len + SECURE_OVERHEAD) : -1;
}

int
secure_open(struct secure_session *s, unsigned char kind, const void *in, size_t len,
    void *out, size_t cap)
{
	const unsigned char *p = in;
	unsigned char nonce[12];
	uint64_t seq = 0, distance;
	uint32_t number;
	struct secure_epoch candidate = {0}, prior = {0}, *epoch;
	EVP_CIPHER_CTX *ctx = NULL;
	int i, n, tail, ok = 0, advancing = 0;
	if (!secure_ready(s) || len < SECURE_OVERHEAD || len > 65535 + SECURE_OVERHEAD ||
	    cap < len - SECURE_OVERHEAD) return -1;
	expire_previous(s);
	number = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
	    ((uint32_t)p[2] << 8) | p[3];
	for (i = 4; i < 12; i++) seq = (seq << 8) | p[i];
	if (seq >= REKEY_RECORDS) return -1;
	if (number == s->rx.number) epoch = &s->rx;
	else if (s->have_previous && number == s->previous.number) epoch = &s->previous;
	else if (number > s->rx.number && number - s->rx.number <= REKEY_MAX_SKIP) {
		/* Never commit keys or discard a replay window based on an
		 * unauthenticated epoch number, even if derivation succeeds. */
		candidate = s->rx;
		while (candidate.number < number) {
			prior = candidate;
			OPENSSL_cleanse(prior.secret, sizeof(prior.secret));
			if (!epoch_next(&candidate)) goto done;
		}
		epoch = &candidate;
		advancing = 1;
	} else return -1;
	if (epoch->seen && seq <= epoch->highest) {
		distance = epoch->highest - seq;
		if (distance >= 64 || (epoch->seen & (UINT64_C(1) << distance))) goto done;
	}
	len -= SECURE_OVERHEAD;
	nonce_for(nonce, epoch->iv, p + 4);
	ctx = EVP_CIPHER_CTX_new();
	if (!ctx) goto done;
	ok = EVP_DecryptInit_ex(ctx, EVP_chacha20_poly1305(), NULL, epoch->key, nonce) &&
	    EVP_DecryptUpdate(ctx, NULL, &n, &kind, 1) &&
	    EVP_DecryptUpdate(ctx, NULL, &n, p, 12) &&
	    EVP_DecryptUpdate(ctx, out, &n, p + 12, (int)len) &&
	    EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, 16, (void *)(p + 12 + len)) &&
	    EVP_DecryptFinal_ex(ctx, (unsigned char *)out + len, &tail);
	if (!ok) {
		OPENSSL_cleanse(out, len);
		goto done;
	}
	if (!epoch->seen || seq > epoch->highest) {
		distance = seq - epoch->highest;
		epoch->seen = distance >= 64 ? 1 : (epoch->seen << distance) | 1;
		epoch->highest = seq;
	} else epoch->seen |= UINT64_C(1) << (epoch->highest - seq);
	if (advancing) {
		OPENSSL_cleanse(&s->previous, sizeof(s->previous));
		OPENSSL_cleanse(&s->rx, sizeof(s->rx));
		s->previous = prior;
		s->previous_until = SECURE_NOW() + REKEY_GRACE_SECONDS;
		s->have_previous = 1;
		s->rx = candidate;
	}
done:
	EVP_CIPHER_CTX_free(ctx);
	OPENSSL_cleanse(&candidate, sizeof(candidate));
	OPENSSL_cleanse(&prior, sizeof(prior));
	return ok ? (int)len : -1;
}
