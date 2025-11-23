#ifndef TIMERFD_COMPAT_H
#define TIMERFD_COMPAT_H

#ifdef __APPLE__
// Ensure struct itimerspec is fully defined before epoll-shim's sys/timerfd.h forward declaration
// We need to include the headers that define struct timespec first
#include <time.h>
#include <sys/time.h>

// On macOS, struct itimerspec is only forward-declared in <time.h>, not fully defined
// We need to provide the full definition here to avoid incomplete type errors
// This matches the POSIX definition
#ifndef _STRUCT_ITIMERSPEC
#define _STRUCT_ITIMERSPEC
struct itimerspec {
	struct timespec it_interval;  /* Timer interval */
	struct timespec it_value;      /* Timer expiration */
};
#endif

#endif

#endif // TIMERFD_COMPAT_H

