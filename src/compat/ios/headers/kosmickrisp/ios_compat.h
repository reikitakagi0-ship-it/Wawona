/*
 * iOS Compatibility Layer
 * Provides implementations of Linux-specific functions for iOS
 */

#ifndef IOS_COMPAT_H
#define IOS_COMPAT_H

#include <sys/types.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdint.h>

#ifdef __APPLE__
#include <Availability.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <Security/SecRandom.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>

/* accept4 - iOS doesn't have accept4, provide fallback */
#ifndef SOCK_NONBLOCK
#define SOCK_NONBLOCK 0x4000
#endif
#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0x20000000
#endif

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

/* memfd_create - fallback to shm_open */
#define MFD_CLOEXEC 0x0001U
#define MFD_ALLOW_SEALING 0x0002U

static inline int memfd_create(const char *name, unsigned int flags) {
   (void)name;  /* Unused on iOS fallback */
   char template[] = "/tmp/memfd-XXXXXX";
   int fd = mkstemp(template);
   if (fd < 0)
      return -1;
   
   unlink(template);
   
   if (flags & MFD_CLOEXEC)
      fcntl(fd, F_SETFD, FD_CLOEXEC);
   
   return fd;
}

/* mremap - not available on iOS, return error */
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

/* getrandom - iOS 12.0+ has arc4random_buf, use SecRandomCopyBytes as fallback */
#include <Security/SecRandom.h>
static inline ssize_t getrandom(void *buf, size_t buflen, unsigned int flags) {
   (void)flags;
   if (SecRandomCopyBytes(kSecRandomDefault, buflen, buf) == errSecSuccess)
      return (ssize_t)buflen;
   errno = EIO;
   return -1;
}

/* random_r - use arc4random as fallback */
#include <stdlib.h>
#include <stdint.h>
struct random_data;
static inline int random_r(struct random_data *buf, int32_t *result) {
   (void)buf;
   *result = (int32_t)arc4random();
   return 0;
}

/* reallocarray - already has fallback in reallocarray.h, but ensure it's detected */
#ifndef HAVE_REALLOCARRAY
#define HAVE_REALLOCARRAY
#endif

/* secure_getenv - iOS doesn't have secure_getenv, use getenv */
static inline char *secure_getenv(const char *name) {
   return getenv(name);
}

/* qsort_s - iOS doesn't have qsort_s, provide fallback using BSD qsort_r */
#include <stdlib.h>
static inline void qsort_s(void *base, size_t nmemb, size_t size,
                           int (*compar)(const void *, const void *, void *),
                           void *thunk) {
   qsort_r(base, nmemb, size, compar, thunk);
}

/* reallocarray - provide implementation */
#define MUL_NO_OVERFLOW ((size_t)1 << (sizeof(size_t) * 4))
static inline void *reallocarray(void *optr, size_t nmemb, size_t size) {
   if ((nmemb >= MUL_NO_OVERFLOW || size >= MUL_NO_OVERFLOW) &&
       nmemb > 0 && SIZE_MAX / nmemb < size) {
      errno = ENOMEM;
      return NULL;
   }
   return realloc(optr, size * nmemb);
}

/* feenableexcept - floating point exception control, not available on iOS */
#include <fenv.h>
static inline int feenableexcept(int excepts) {
   (void)excepts;
   return 0; /* iOS doesn't support floating point exceptions */
}

/* getisax - Solaris-specific, not available on iOS */
#include <stdint.h>
#include <stddef.h>
static inline int getisax(uint32_t *array, size_t n) {
   (void)array;
   (void)n;
   return 0; /* Not available on iOS */
}

/* dl_iterate_phdr - dynamic linker iteration, not available on iOS */
#include <link.h>
static inline int dl_iterate_phdr(int (*callback)(struct dl_phdr_info *, size_t, void *), void *data) {
   (void)callback;
   (void)data;
   return 0; /* Not available on iOS */
}

/* thrd_create - C11 threads, use pthreads as fallback */
#include <pthread.h>
#include <threads.h>
#include <errno.h>
static inline int thrd_create(thrd_t *thr, thrd_start_t func, void *arg) {
   pthread_t thread;
   int ret = pthread_create(&thread, NULL, (void*(*)(void*))func, arg);
   if (ret == 0) {
      *thr = (thrd_t)thread;
      return thrd_success;
   }
   return thrd_error;
}

/* thrd_start_t type definition for compatibility */
typedef int (*thrd_start_t)(void *);

#endif /* __APPLE__ */

#endif /* IOS_COMPAT_H */

