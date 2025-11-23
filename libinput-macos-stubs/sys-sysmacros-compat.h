#ifndef SYS_SYSMACROS_COMPAT_H
#define SYS_SYSMACROS_COMPAT_H

#ifdef __APPLE__
// macOS compatibility for sys/sysmacros.h
// On macOS, major(), minor(), and makedev() are defined in <sys/types.h>
// This header provides compatibility for code that expects sys/sysmacros.h

#include <sys/types.h>

// The macros are already defined in sys/types.h on macOS:
//   major(dev)    - extracts major device number
//   minor(dev)    - extracts minor device number  
//   makedev(maj, min) - creates dev_t from major and minor numbers

// No additional definitions needed - they're already in sys/types.h
// This header just ensures sys/types.h is included when sys/sysmacros.h is expected

#endif // __APPLE__

#endif // SYS_SYSMACROS_COMPAT_H

