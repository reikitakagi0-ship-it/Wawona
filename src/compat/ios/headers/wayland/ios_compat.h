/*
 * iOS Compatibility Layer for Wayland
 * Provides implementations of Linux-specific functions for iOS
 */

#ifndef WAYLAND_IOS_COMPAT_H
#define WAYLAND_IOS_COMPAT_H

#include <sys/types.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

#ifdef __APPLE__

#ifndef SOCK_NONBLOCK
#define SOCK_NONBLOCK 0x4000
#endif
#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0x20000000
#endif

/* accept4 - iOS doesn't have accept4, provide fallback */
static inline int accept4(int sockfd, struct sockaddr *addr, socklen_t *addrlen, int flags) {
   int fd = accept(sockfd, addr, addrlen);
   if (fd < 0)
      return -1;
   
   if (flags & SOCK_NONBLOCK) {
      int opts = fcntl(fd, F_GETFL);
      if (opts >= 0)
         fcntl(fd, F_SETFL, opts | O_NONBLOCK);
   }
   
   if (flags & SOCK_CLOEXEC) {
      fcntl(fd, F_SETFD, FD_CLOEXEC);
   }
   
   return fd;
}

/* posix_fallocate - fallback implementation */
static inline int posix_fallocate(int fd, off_t offset, off_t len) {
   if (ftruncate(fd, offset + len) < 0)
      return errno;
   return 0;
}

/* memfd_create - fallback to temp file */
#define MFD_CLOEXEC 0x0001U
#define MFD_ALLOW_SEALING 0x0002U
#define MFD_NOEXEC_SEAL 0x0004U

/* File sealing constants (not available on iOS, define stubs) */
#ifndef F_ADD_SEALS
#define F_ADD_SEALS 1033
#endif
#ifndef F_GET_SEALS
#define F_GET_SEALS 1034
#endif
#ifndef F_SEAL_SEAL
#define F_SEAL_SEAL 0x0001
#endif
#ifndef F_SEAL_SHRINK
#define F_SEAL_SHRINK 0x0002
#endif
#ifndef F_SEAL_GROW
#define F_SEAL_GROW 0x0004
#endif
#ifndef F_SEAL_WRITE
#define F_SEAL_WRITE 0x0008
#endif

static inline int memfd_create(const char *name, unsigned int flags) {
   (void)name;  /* Unused on iOS fallback */
   char template[] = "/tmp/memfd-XXXXXX";
   extern int mkstemp(char *template);
   int fd = mkstemp(template);
   if (fd < 0)
      return -1;
   
   unlink(template);
   
   if (flags & MFD_CLOEXEC)
      fcntl(fd, F_SETFD, FD_CLOEXEC);
   
   return fd;
}

/* mremap - not available on iOS, return error */
#include <sys/mman.h>
static inline void *mremap(void *old_address, size_t old_size, size_t new_size, int flags, ...) {
   (void)old_address;
   (void)old_size;
   (void)new_size;
   (void)flags;
   errno = ENOSYS;
   return MAP_FAILED;
}

/* prctl - not available on iOS, stub implementation */
#define PR_SET_NAME 15
#define PR_GET_NAME 16

static inline int prctl(int option, ...) {
   (void)option;
   errno = ENOSYS;
   return -1;
}

#endif /* __APPLE__ */

#endif /* WAYLAND_IOS_COMPAT_H */

