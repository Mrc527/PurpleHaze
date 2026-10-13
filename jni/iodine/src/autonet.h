/* ISC license; see LICENSE. CLI-only network configuration guardian. */
#ifndef IODINE_AUTONET_H
#define IODINE_AUTONET_H
int autonet_start(const char *device, const char *endpoint);
void autonet_stop(void);
#endif
