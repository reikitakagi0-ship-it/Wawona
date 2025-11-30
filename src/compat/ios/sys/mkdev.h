/*
 * iOS Compatibility: sys/mkdev.h
 */

#ifndef _SYS_MKDEV_H
#define _SYS_MKDEV_H

#include <sys/types.h>

/* iOS already provides major/minor/makedev in sys/types.h */
/* This header exists for compatibility but doesn't redefine them */

#endif /* _SYS_MKDEV_H */

