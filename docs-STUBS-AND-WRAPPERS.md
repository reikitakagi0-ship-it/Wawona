# Stubs and Wrappers for iOS/macOS Build

This document describes all the stubs, wrappers, and compatibility layers created to enable KosmicKrisp (Mesa) and Wayland compositor builds on macOS/iOS.

## Overview

Many Linux-specific libraries and system calls are not available on macOS/iOS. To enable cross-platform builds, we create:
1. **pkg-config stubs** - Satisfy Meson's dependency checks
2. **Header stubs** - Provide minimal type definitions for compilation
3. **Library wrappers** - Full implementations (like GBM) that map Linux APIs to Apple APIs

## Complete List of Stubs

### 1. pkg-config Stubs (`.pc` files)

All stubs are located in `src/compat/macos/stubs/libinput-macos/` and are automatically installed during iOS build.

#### Runtime Dependencies (Optional)
- **libdisplay-info.pc** - Display information library (optional)
- **libelf.pc** - ELF file manipulation (Linux-specific, not needed)
- **lua.pc, lua-5.3.pc, lua-5.4.pc, lua5.3.pc, lua5.4.pc, lua53.pc, lua54.pc** - Lua scripting language (optional, all variants)
- **valgrind.pc** - Memory debugging tool (development tool, not needed)

#### Already Existing Stubs
- **libudev-stub.pc** - Linux device management (not needed on macOS/iOS)
- **libdrm-stub.pc** - DRM interface (stub, real headers installed separately)
- **libevdev-stub.pc** - Linux input events (not needed)
- **mtdev-stub.pc** - Multi-touch device (not needed)
- **hwdata-stub.pc** - Hardware data (optional)
- **egl-stub.pc, gbm-stub.pc, glesv2-stub.pc** - Graphics APIs (some have full implementations)

### 2. Header Stubs

Located in `src/compat/macos/stubs/libinput-macos/include/`:

- **libdisplay-info.h** - Minimal type definitions
- **libelf.h** - ELF types (not used on macOS/iOS)
- **lua.h** - Lua types (optional)
- **valgrind/valgrind.h** - Valgrind macros (all no-ops)

### 3. Full Implementations (Wrappers)

#### GBM (Generic Buffer Management) - 100% Complete
- **File**: `src/compat/macos/stubs/libinput-macos/gbm-wrapper.c` (639 lines)
- **Header**: `src/compat/macos/stubs/libinput-macos/gbm.h`
- **Implementation**: Complete GBM API using IOSurface/Metal
- **Status**: ✅ 100% complete - All GBM functions implemented
- **Features**:
  - Device management
  - Buffer object creation/destruction
  - Surface API (critical for EGL)
  - Format support (9 formats)
  - CPU buffer mapping
  - Cross-process sharing via IOSurface IDs

## Installation Process

The `install-kosmickrisp.sh` script automatically:

1. **Installs stub pkg-config files** before Meson configuration
   - Copies all `.pc` files from stubs directory
   - Updates prefix to point to install directory
   - Makes them available to pkg-config

2. **Installs stub headers** before Meson configuration
   - Copies headers recursively to include directory
   - Ensures compilation checks pass

3. **Configures PKG_CONFIG_LIBDIR** to include:
   - Install directory (`ios-install/lib/pkgconfig`)
   - Bootstrap tools directory
   - Stubs directory (fallback)

## Expected "NO" Entries (Harmless)

These are **expected** and **harmless** - they're Linux-specific features that don't exist on macOS/iOS:

### System Calls (Expected to be NO)
- `sched_getaffinity` - CPU affinity (Linux-specific)
- `memfd_create` - Memory file descriptors (Linux-specific)
- `getrandom` - Random number generation (use `arc4random` on macOS/iOS)
- `random_r` - Reentrant random (Linux-specific)
- `posix_fallocate` - File preallocation (not available on macOS)
- `secure_getenv` - Secure environment access (Linux-specific)
- `reallocarray` - Reallocation helper (use standard functions)
- `feenableexcept` - Floating point exceptions (Linux-specific)
- `getisax` - Instruction set availability (Solaris-specific)
- `thrd_create` - Thread creation (use pthreads)
- `dl_iterate_phdr` - Dynamic linker iteration (Linux-specific)
- `qsort_s` - Secure quicksort (Windows-specific)

### Headers (Expected to be NO)
- `sys/prctl.h` - Process control (Linux-specific)
- `sys/procctl.h` - Process control (FreeBSD-specific)
- `linux/futex.h` - Fast userspace mutex (Linux-specific)
- `linux/udmabuf.h` - Userspace DMA buffer (Linux-specific)
- `linux/inotify.h` - File system events (Linux-specific)

### Compiler Features (Expected to be NO)
- `__builtin_add_overflow_p` - Overflow checking (GCC-specific, newer)
- `__builtin_sub_overflow_p` - Overflow checking (GCC-specific, newer)
- `gc-sections` linker flag - Garbage collect sections (not critical)
- `__builtin_ia32_clflushopt` - x86-specific instruction (not needed on ARM)

### Libraries (Optional - NO is OK)
- **ws2_32** - Windows sockets (not needed)
- **sensors** - Hardware sensors (optional)
- **vtn_bindgen2** - Code generation tool (optional)

## Build Integration

All stubs are automatically:
1. ✅ Installed before Meson configuration
2. ✅ Available via pkg-config
3. ✅ Headers available for compilation
4. ✅ Properly configured in PKG_CONFIG_LIBDIR

## Verification

After running `install-kosmickrisp.sh --platform ios`, you should see:
- All stub `.pc` files in `build/ios-install/lib/pkgconfig/`
- All stub headers in `build/ios-install/include/`
- Meson configuration will find these stubs
- Build will proceed without dependency errors

## Notes

- **Stubs are minimal** - They satisfy pkg-config checks but don't provide functionality
- **Optional dependencies** - Missing optional deps won't break the build
- **Linux-specific features** - Many "NO" entries are expected and harmless
- **GBM is special** - It's a full implementation, not just a stub

## Future Improvements

If needed, we can create full implementations for:
- **libdisplay-info** - If display info queries are needed
- **lua** - If scripting support is required
- Other optional dependencies as needed

