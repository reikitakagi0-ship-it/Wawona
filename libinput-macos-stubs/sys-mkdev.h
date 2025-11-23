#ifndef SYS_MKDEV_H
#define SYS_MKDEV_H

#ifdef __APPLE__
// macOS compatibility for sys/mkdev.h
// On macOS, major(), minor(), and makedev() are defined in <sys/types.h>
// This header provides compatibility for code that expects sys/mkdev.h

#include <sys/types.h>

// The macros are already defined in sys/types.h on macOS:
//   major(dev)    - extracts major device number
//   minor(dev)    - extracts minor device number  
//   makedev(maj, min) - creates dev_t from major and minor numbers

// No additional definitions needed - they're already in sys/types.h
// This header just ensures sys/types.h is included when sys/mkdev.h is expected

#endif // __APPLE__

#endif // SYS_MKDEV_H

