/*
 * iOS Compatibility: sys/prctl.h
 */

#ifndef _SYS_PRCTL_H
#define _SYS_PRCTL_H

#include <errno.h>
#include <sys/types.h>
#include <stdarg.h>

#define PR_SET_NAME 15
#define PR_GET_NAME 16
#define PR_SET_PDEATHSIG 1
#define PR_GET_PDEATHSIG 2

static inline int prctl(int option, ...) {
   (void)option;
   errno = ENOSYS;
   return -1;
}

#endif /* _SYS_PRCTL_H */

