/*
 * iOS System Header Compatibility
 * Provides compatibility headers for Linux-specific system headers
 */

#ifndef IOS_SYS_HEADERS_H
#define IOS_SYS_HEADERS_H

#ifdef __APPLE__

#include <errno.h>
#include <sys/types.h>

/* sys/prctl.h - Linux process control */
#ifndef _SYS_PRCTL_H
#define _SYS_PRCTL_H

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

/* sys/procctl.h - FreeBSD process control */
#ifndef _SYS_PROCCTL_H
#define _SYS_PROCCTL_H

#define PROC_REAP_ACQUIRE 1
#define PROC_REAP_RELEASE 2

static inline int procctl(int idtype, id_t id, int cmd, void *data) {
   (void)idtype;
   (void)id;
   (void)cmd;
   (void)data;
   errno = ENOSYS;
   return -1;
}

#endif /* _SYS_PROCCTL_H */

/* sys/sysmacros.h - Linux device major/minor macros */
/* Note: iOS already has major/minor/makedev in sys/types.h, so we don't redefine them */
#ifndef SYS_SYSMACROS_H
#define SYS_SYSMACROS_H
/* iOS already provides these via sys/types.h */
#endif /* SYS_SYSMACROS_H */

/* sys/mkdev.h - BSD device major/minor macros */
/* Note: iOS already has major/minor/makedev in sys/types.h, so we don't redefine them */
#ifndef SYS_MKDEV_H
#define SYS_MKDEV_H
/* iOS already provides these via sys/types.h */
#endif /* SYS_MKDEV_H */

#endif /* __APPLE__ */

#endif /* IOS_SYS_HEADERS_H */

