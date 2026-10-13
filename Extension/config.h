/*
 * iOS arm64 configuration for the shared iodine client.
 */

#pragma once

#define ARCH_IS_BIG_ENDIAN 0

#define CAN_DETACH 0

#define DARWIN 1

#define HAVE_ARC4RANDOM_BUF 1

#define HAVE_CHECKTOKENMEMBERSHIP 0

#define HAVE_CHROOT 1

#define HAVE_DAEMON 0

#define HAVE_FD_CLOEXEC 1

#define HAVE_GETEUID 1

#define HAVE_GETPWNAM 1

#define HAVE_GETRANDOM 0

#define HAVE_INET_ATON 1

#define HAVE_NORETURN_ATTR 1

#define HAVE_PROGNAME 0

#define HAVE_SETGROUPS 1

#define HAVE_STRLCPY 1

#define HAVE_SYSLOG 1

#define HAVE_WARNX 1

#define IODINE_VERSION "0.8.0-ios-602"

#define TUNNEL_DEV_PATH "/dev/net/tun"
