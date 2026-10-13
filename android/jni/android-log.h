#ifndef IODINE_ANDROID_LOG_H
#define IODINE_ANDROID_LOG_H
#include <stdio.h>
#include <err.h>
int iodine_android_fprintf(FILE *, const char *, ...);
int iodine_android_printf(const char *, ...);
void iodine_android_warn(const char *, ...);
void iodine_android_warnx(const char *, ...);
void android_log_callback(const char *);
#endif
