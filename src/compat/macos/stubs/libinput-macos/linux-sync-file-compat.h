#ifndef LINUX_SYNC_FILE_COMPAT_H
#define LINUX_SYNC_FILE_COMPAT_H

#ifdef __APPLE__
// macOS compatibility for linux/sync_file.h
// This provides the same structures and ioctls as the Linux kernel header

#include <sys/ioctl.h>
#include <stdint.h>

// Linux kernel types
typedef uint64_t __u64;
typedef uint32_t __u32;
typedef uint16_t __u16;
typedef uint8_t __u8;
typedef int32_t __s32;
typedef int16_t __s16;
typedef int8_t __s8;

struct sync_fence_info {
	char obj_name[32];
	char driver_name[32];
	__s32 status;
	__u32 flags;
	__u64 timestamp_ns;
};

struct sync_file_info {
	char name[32];
	__s32 status;
	__u32 flags;
	__u32 num_fences;
	__u32 pad;
	__u64 sync_fence_info;
};

// IOCTL definitions
#define SYNC_IOC_MAGIC '>'
#ifndef _IOC_NRBITS
#define _IOC_NRBITS     8
#define _IOC_TYPEBITS   8
#define _IOC_SIZEBITS   14
#define _IOC_DIRBITS    2

#define _IOC_NRSHIFT    0
#define _IOC_TYPESHIFT  (_IOC_NRSHIFT+_IOC_NRBITS)
#define _IOC_SIZESHIFT  (_IOC_TYPESHIFT+_IOC_TYPEBITS)
#define _IOC_DIRSHIFT   (_IOC_SIZESHIFT+_IOC_SIZEBITS)

#define _IOC_NONE  0U
#define _IOC_WRITE 1U
#define _IOC_READ  2U
#endif

#ifndef _IOC
#define _IOC(dir,type,nr,size) \
	(((dir)  << _IOC_DIRSHIFT) | \
	 ((type) << _IOC_TYPESHIFT) | \
	 ((nr)   << _IOC_NRSHIFT) | \
	 ((size) << _IOC_SIZESHIFT))
#endif

#ifndef _IOWR
#define _IOWR(type,nr,size) _IOC(_IOC_READ|_IOC_WRITE,(type),(nr),sizeof(size))
#endif

#define SYNC_IOC_FILE_INFO _IOWR(SYNC_IOC_MAGIC, 4, struct sync_file_info)

// Note: On macOS, sync_file ioctls will fail at runtime since they're Linux-specific
// The structures are provided for compilation compatibility only

#endif // __APPLE__

#endif // LINUX_SYNC_FILE_COMPAT_H

