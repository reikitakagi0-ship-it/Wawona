# iOS Compatibility Layer

This directory contains iOS compatibility implementations for Linux-specific functions and headers.

## Structure

- `headers/` - Compatibility headers (ios_compat.h, etc.)
- `functions/` - Function implementations
- `sys/` - System header compatibility (sys/prctl.h, sys/procctl.h, etc.)

## Usage

Include compatibility headers in your code:

```c
#ifdef __APPLE__
#include "compat/ios/headers/ios_compat.h"
#include "compat/ios/sys/prctl.h"
#endif
```

## Functions Provided

- `accept4` - Socket accept with flags
- `memfd_create` - Memory file descriptor creation
- `mremap` - Memory remapping
- `prctl` - Process control
- `getrandom` - Random number generation
- `reallocarray` - Safe reallocation
- `qsort_s` - Safe quicksort
- `secure_getenv` - Secure environment variable access
- `thrd_create` - Thread creation
- `dl_iterate_phdr` - Dynamic linker iteration
- `feenableexcept` - Floating point exception control
- `getisax` - Instruction set availability

## System Headers

- `sys/prctl.h` - Process control
- `sys/procctl.h` - Process control (FreeBSD)
- `sys/sysmacros.h` - Device macros
- `sys/mkdev.h` - Device creation

## Integration

Compatibility headers are automatically included when:
- Cross-compiling for iOS (`meson.is_cross_build()` and `host_machine.system() == 'darwin'`)
- Building with iOS SDK (`CMAKE_SYSTEM_NAME == "iOS"`)

## Maintenance

When adding new compatibility functions:
1. Add function to `headers/ios_compat.h`
2. Update build system to detect function
3. Document function in this README
4. Add tests if applicable

