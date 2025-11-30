/*
 * iOS Compatibility: sys/procctl.h
 */

#ifndef _SYS_PROCCTL_H
#define _SYS_PROCCTL_H

#include <errno.h>
#include <sys/types.h>

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

