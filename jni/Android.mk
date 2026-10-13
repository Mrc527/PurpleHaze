LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := openssl_crypto
LOCAL_SRC_FILES := ../.deps/$(TARGET_ARCH_ABI)/lib/libcrypto.a
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)/../.deps/$(TARGET_ARCH_ABI)/include
include $(PREBUILT_STATIC_LIBRARY)
include $(CLEAR_VARS)
LOCAL_MODULE := openssl_ssl
LOCAL_SRC_FILES := ../.deps/$(TARGET_ARCH_ABI)/lib/libssl.a
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)/../.deps/$(TARGET_ARCH_ABI)/include
include $(PREBUILT_STATIC_LIBRARY)
include $(CLEAR_VARS)
LOCAL_MODULE := iodine-client
LOCAL_LDLIBS := -lz -llog
LOCAL_CFLAGS := -std=c11 -D_GNU_SOURCE -Wall -Wextra -Wno-unused-parameter -fvisibility=hidden
LOCAL_C_INCLUDES := $(LOCAL_PATH) $(LOCAL_PATH)/iodine/src
LOCAL_STATIC_LIBRARIES := openssl_ssl openssl_crypto
LOCAL_SRC_FILES := iodine-client.c android-tun.c android-log.c \
 iodine/src/base32.c iodine/src/base64.c iodine/src/base128.c \
 iodine/src/common.c iodine/src/compat.c iodine/src/dns.c \
 iodine/src/read.c iodine/src/encoding.c iodine/src/login.c \
 iodine/src/md5.c iodine/src/client.c iodine/src/secure.c
include $(BUILD_SHARED_LIBRARY)
