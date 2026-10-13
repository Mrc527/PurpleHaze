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
LOCAL_C_INCLUDES := $(LOCAL_PATH) $(LOCAL_PATH)/../../vendor/iodine/src
LOCAL_STATIC_LIBRARIES := openssl_ssl openssl_crypto
LOCAL_SRC_FILES := iodine-client.c android-tun.c android-log.c \
 ../../vendor/iodine/src/base32.c ../../vendor/iodine/src/base64.c ../../vendor/iodine/src/base128.c \
 ../../vendor/iodine/src/common.c ../../vendor/iodine/src/compat.c ../../vendor/iodine/src/dns.c \
 ../../vendor/iodine/src/read.c ../../vendor/iodine/src/encoding.c ../../vendor/iodine/src/login.c \
 ../../vendor/iodine/src/md5.c ../../vendor/iodine/src/client.c ../../vendor/iodine/src/secure.c
include $(BUILD_SHARED_LIBRARY)
