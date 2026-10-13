/* ISC license; see iodine/LICENSE. One native session, owned by the VPN worker. */
#include <jni.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <openssl/crypto.h>
#include "iodine/src/common.h"
#include "iodine/src/client.h"
#include "iodine/src/encoding.h"
#include "android-tun.h"
static int dns_fd = -1;
static char *domain;
static JavaVM *vm;
static jclass callback_class;
static jmethodID callback_method;
JNIEXPORT jint JNI_OnLoad(JavaVM *value, void *reserved) {
    (void)reserved;
    JNIEnv *env = NULL; vm = value;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    jclass cls = (*env)->FindClass(env, "ch/visin/purplehaze/NativeTunnel");
    if (!cls) return JNI_ERR;
    callback_class = (*env)->NewGlobalRef(env, cls);
    callback_method = (*env)->GetStaticMethodID(env, cls, "log_callback", "(Ljava/lang/String;)V");
    (*env)->DeleteLocalRef(env, cls);
    return callback_class && callback_method ? JNI_VERSION_1_6 : JNI_ERR;
}
void android_log_callback(const char *msg) {
    JNIEnv *env = NULL;
    if (!vm || (*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return;
    jstring text = (*env)->NewStringUTF(env, msg);
    if (!text) return;
    (*env)->CallStaticVoidMethod(env, callback_class, callback_method, text);
    (*env)->DeleteLocalRef(env, text);
    if ((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);
}
static void cleanup(void) {
    if (dns_fd >= 0) close(dns_fd);
    dns_fd = -1;
    client_cleanup();
    free(domain); domain = NULL;
}
static char *copy_string(JNIEnv *env, jstring value) {
    if (!value) return NULL;
    const char *p = (*env)->GetStringUTFChars(env, value, NULL);
    if (!p) return NULL;
    char *copy = strdup(p);
    (*env)->ReleaseStringUTFChars(env, value, p);
    return copy;
}
JNIEXPORT jint JNICALL Java_ch_visin_purplehaze_NativeTunnel_prepare(
    JNIEnv *env, jclass cls, jstring server, jstring topdomain, jstring password,
    jbyteArray key, jboolean proxy, jboolean lazy, jint hostlen, jstring qtype) {
    cleanup();
    memset(&android_tun, 0, sizeof(android_tun));
    char *host = copy_string(env, server), *pass = copy_string(env, password);
    char *type = copy_string(env, qtype), *error = NULL;
    domain = copy_string(env, topdomain);
    struct sockaddr_storage addr;
    socklen_t addrlen;
    int result = -1;
    unsigned char bytes[32] = {0};
    if (!host || !pass || !type || !domain || hostlen < 100 || hostlen > 255 ||
        check_topdomain(domain, 0, &error) || hostname_need(domain) > (size_t)hostlen ||
        get_addr(host, DNS_PORT, AF_UNSPEC, AI_NUMERICHOST, &addr, &addrlen)) goto out;
    if (key && ((*env)->GetArrayLength(env, key) != 32 || pass[0])) goto out;
    if (proxy && !key) goto out;
    client_init();
    if (key) {
        (*env)->GetByteArrayRegion(env, key, 0, 32, (jbyte *)bytes);
        if ((*env)->ExceptionCheck(env) || !client_set_key(bytes, sizeof(bytes))) goto out;
    } else client_set_password(pass);
    client_set_proxy(proxy);
    client_set_nameserver(&addr, (int)addrlen);
    client_set_topdomain(domain);
    client_set_selecttimeout(1);
    client_set_lazymode(lazy);
    client_set_hostname_maxlen(hostlen);
    if (type[0] && client_set_qtype(type)) goto out;
    dns_fd = open_dns_from_host(NULL, 0, addr.ss_family, AI_PASSIVE);
    result = dns_fd;
out:
    OPENSSL_cleanse(bytes, sizeof(bytes));
    if (pass) OPENSSL_cleanse(pass, strlen(pass));
    free(host); free(pass); free(type);
    if (result < 0) cleanup();
    return result;
}
JNIEXPORT jint JNICALL Java_ch_visin_purplehaze_NativeTunnel_handshake(
    JNIEnv *env, jclass cls, jboolean raw, jint fragment) {
    if (dns_fd < 0 || fragment < 0 || fragment > 65535) return 1;
    return client_handshake(dns_fd, raw, fragment == 0, fragment);
}
JNIEXPORT jint JNICALL Java_ch_visin_purplehaze_NativeTunnel_tunnel(JNIEnv *env, jclass cls, jint fd) {
    if (dns_fd < 0 || fd < 0) return 1;
    return client_tunnel(fd, dns_fd);
}
JNIEXPORT void JNICALL Java_ch_visin_purplehaze_NativeTunnel_tunnelInterrupt(JNIEnv *env, jclass cls) {
    client_stop(); /* Atomic in the vendored Android adapter. Worker closes descriptors. */
}
JNIEXPORT void JNICALL Java_ch_visin_purplehaze_NativeTunnel_cleanup(JNIEnv *env, jclass cls) { cleanup(); }
JNIEXPORT jstring JNICALL Java_ch_visin_purplehaze_NativeTunnel_getIp(JNIEnv *env, jclass cls) {
    return (*env)->NewStringUTF(env, android_tun.ip);
}
JNIEXPORT jstring JNICALL Java_ch_visin_purplehaze_NativeTunnel_getRemoteIp(JNIEnv *env, jclass cls) {
    return (*env)->NewStringUTF(env, android_tun.peer);
}
JNIEXPORT jint JNICALL Java_ch_visin_purplehaze_NativeTunnel_getNetbits(JNIEnv *env, jclass cls) { return android_tun.netbits; }
JNIEXPORT jint JNICALL Java_ch_visin_purplehaze_NativeTunnel_getMtu(JNIEnv *env, jclass cls) { return android_tun.mtu; }

JNIEXPORT jint JNICALL Java_ch_visin_purplehaze_NativeTunnel_configureTransport(JNIEnv *env, jclass cls, jint timeout, jstring encoding) {
    if (dns_fd < 0 || timeout < 1 || timeout > 60) return 1;
    char *value = copy_string(env, encoding);
    if (!value) return 1;
    int valid = !value[0] || !strcmp(value, "base32") || !strcmp(value, "base64") ||
        !strcmp(value, "base64u") || !strcmp(value, "base128") || !strcmp(value, "raw");
    if (valid) { client_set_selecttimeout(timeout); if (value[0]) client_set_downenc(value); }
    free(value); return valid ? 0 : 1;
}
