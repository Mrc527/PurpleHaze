/* ISC license; see ../../vendor/iodine/LICENSE. Credentials are never included in messages. */
#include "android-log.h"
#include <android/log.h>
#include <stdarg.h>
static int message(const char *fmt, va_list args) {
    char text[2048];
    int n = vsnprintf(text, sizeof(text), fmt, args);
    __android_log_write(ANDROID_LOG_INFO, "iodine", text);
    android_log_callback(text);
    return n;
}
int iodine_android_fprintf(FILE *stream, const char *fmt, ...) {
    (void)stream; va_list args; va_start(args, fmt); int n = message(fmt, args); va_end(args); return n;
}
int iodine_android_printf(const char *fmt, ...) {
    va_list args; va_start(args, fmt); int n = message(fmt, args); va_end(args); return n;
}
void iodine_android_warn(const char *fmt, ...) {
    va_list args; va_start(args, fmt); message(fmt, args); va_end(args);
}
void iodine_android_warnx(const char *fmt, ...) {
    va_list args; va_start(args, fmt); message(fmt, args); va_end(args);
}
