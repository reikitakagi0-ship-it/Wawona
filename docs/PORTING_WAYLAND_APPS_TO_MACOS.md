# Porting Wayland Applications to macOS

This guide explains how to port Wayland applications to macOS, covering common issues and solutions encountered when building Linux-centric Wayland software on macOS.

## Overview

Wayland applications are typically designed for Linux systems and rely on Linux-specific APIs and libraries. Porting them to macOS requires addressing several categories of compatibility issues:

1. **Linux-specific headers** (`linux/input.h`, `linux/dma-buf.h`, etc.)
2. **Linux-specific libraries** (`libinput`, `libevdev`, `libdrm`, `libudev`)
3. **System differences** (clocks, file systems, process management)
4. **Build system configuration** (Meson, CMake, pkg-config)

## Common Issues and Solutions

### 1. Linux Input Headers (`linux/input.h`)

**Problem**: macOS doesn't have Linux kernel headers like `linux/input.h`.

**Solution**: Create a compatibility header that provides the necessary definitions.

**Example**: Create `linux-input-compat.h`:

```c
#ifndef LINUX_INPUT_COMPAT_H
#define LINUX_INPUT_COMPAT_H

#ifdef __APPLE__

// macOS compatibility header for linux/input.h
// Provides minimal definitions needed for Wayland input handling

#include <stdint.h>

// Input event types
#define EV_SYN           0x00
#define EV_KEY           0x01
#define EV_REL           0x02
#define EV_ABS           0x03
#define EV_MSC           0x04
#define EV_SW            0x05
#define EV_LED           0x11
#define EV_SND           0x12
#define EV_REP           0x14
#define EV_FF            0x15
#define EV_PWR           0x16
#define EV_FF_STATUS     0x17
#define EV_MAX           0x1f
#define EV_CNT           (EV_MAX+1)

// Key codes (subset - add more as needed)
#define KEY_RESERVED      0
#define KEY_ESC           1
#define KEY_1             2
#define KEY_2             3
// ... add more key codes as needed

// Input device capabilities
#define ABS_X             0x00
#define ABS_Y             0x01
#define ABS_Z             0x02
// ... add more as needed

// Input event structure
struct input_event {
    struct timeval time;
    uint16_t type;
    uint16_t code;
    int32_t value;
};

#endif // __APPLE__

#endif // LINUX_INPUT_COMPAT_H
```

**Usage**: Replace includes in source files:

```c
#ifdef __APPLE__
#include "linux-input-compat.h"
#else
#include <linux/input.h>
#endif
```

### 2. Linux-Specific Libraries

#### libinput

**Problem**: `libinput` is Linux-specific but can be ported to macOS.

**Solution**: 
- Build `libinput` from source with macOS patches
- Use pkg-config to detect locally built version
- Add build directory to `PKG_CONFIG_PATH`:

```bash
export PKG_CONFIG_PATH="/path/to/libinput/build-macos/meson-private:$PKG_CONFIG_PATH"
```

#### libevdev, libdrm, libudev

**Problem**: These libraries are Linux-specific and not available on macOS.

**Solution**: Create stub `.pc` files and headers:

**Example stub `.pc` file** (`libevdev.pc`):

```ini
prefix=/opt/homebrew
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: libevdev
Description: Linux input device library (macOS stub)
Version: 1.13.0
Libs: 
Cflags: -I${includedir}
```

**Example stub header** (`libevdev.h`):

```c
#ifndef LIBEVDEV_H
#define LIBEVDEV_H

#ifdef __APPLE__

// macOS stub for libevdev
typedef struct libevdev libevdev;

// Minimal stub functions - implement as no-ops or return errors
int libevdev_new_from_fd(int fd, struct libevdev **dev);
void libevdev_free(struct libevdev *dev);
// ... add more stubs as needed

#endif // __APPLE__

#endif // LIBEVDEV_H
```

### 3. DMA-BUF and UDMABUF

**Problem**: `linux/dma-buf.h` and `linux/udmabuf.h` are Linux kernel interfaces.

**Solution**: Guard DMA-BUF code with `#ifndef __APPLE__`:

```c
#ifndef __APPLE__
#include <linux/dma-buf.h>
#include <linux/udmabuf.h>

// DMA-BUF implementation
struct dma_buf *create_dmabuf(...) {
    // Linux implementation
}

#else
// macOS stub - return NULL or use alternative implementation
struct dma_buf *create_dmabuf(...) {
    return NULL; // or implement using Metal/CoreVideo
}
#endif
```

### 4. System Clock Differences

**Problem**: `CLOCK_MONOTONIC_COARSE` is Linux-specific.

**Solution**: Define compatibility macro:

```c
#ifdef __APPLE__
#ifndef CLOCK_MONOTONIC_COARSE
#define CLOCK_MONOTONIC_COARSE CLOCK_MONOTONIC
#endif
#endif
```

### 5. Input Event Structure Redefinition

**Problem**: When using libinput (which includes its own `input.h`), defining `struct input_event` in the compatibility header causes redefinition errors.

**Solution**: Guard the compatibility header definition to avoid conflicts with libinput:

```c
#ifndef LINUX_INPUT_COMPAT_H
#define LINUX_INPUT_COMPAT_H

#ifdef __APPLE__

// Check if libinput headers already define input_event
// libinput includes its own input.h which defines input_event
// We check for _UAPI_INPUT_H which libinput's input.h defines
#ifndef _UAPI_INPUT_H
// ... compatibility definitions ...
struct input_event {
    struct timeval time;
    uint16_t type;
    uint16_t code;
    int32_t value;
};
#endif // _UAPI_INPUT_H
#endif // __APPLE__

#endif // LINUX_INPUT_COMPAT_H
```

**Important**: Files that include `libinput.h` should NOT include `linux-input-compat.h` since libinput provides its own input.h. Only include the compatibility header in files that need input.h but don't use libinput.

### 6. itimerspec Structure

### 7. Process Management (`pty.h`)

**Problem**: macOS uses different process management APIs.

**Solution**: Use compatibility wrapper:

```c
#ifdef __APPLE__
#include "util.h"  // or create compatibility functions
#else
#include <pty.h>
#endif
```

### 8. Build System Configuration

#### Meson Build System

**Problem**: Meson dependencies fail on macOS.

**Solution**: Make dependencies optional and provide fallbacks:

```meson
# Make libinput optional
dep_libinput = dependency('libinput', required: false)

# Use stub if not found
if not dep_libinput.found()
    dep_libinput = declare_dependency(
        include_directories: include_directories('../../libinput-macos-stubs')
    )
endif
```

**Example**: Patch `meson.build` to handle macOS:

```python
# In build script
import re

meson_build = "meson.build"
with open(meson_build, 'r') as f:
    content = f.read()

# Make libinput optional
pattern = r"dep_libinput = dependency\('libinput', required: true\)"
replacement = r"dep_libinput = dependency('libinput', required: false)"
content = re.sub(pattern, replacement, content)

with open(meson_build, 'w') as f:
    f.write(content)
```

#### PKG_CONFIG_PATH Setup

**Solution**: Prioritize locally built libraries:

```bash
# Setup PKG_CONFIG_PATH early
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# Add locally built dependencies
if [ -f "$PROJECT_ROOT/libinput/build-macos/meson-private/libinput.pc" ]; then
    export PKG_CONFIG_PATH="$PROJECT_ROOT/libinput/build-macos/meson-private:$PKG_CONFIG_PATH"
fi

# Add stubs as fallback
if [ -d "$PROJECT_ROOT/libinput-macos-stubs" ]; then
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$PROJECT_ROOT/libinput-macos-stubs"
fi
```

## Step-by-Step Porting Process

### 1. Identify Dependencies

```bash
# Check what dependencies the project needs
meson setup build
# Review meson-logs/meson-log.txt for missing dependencies
```

### 2. Create Stub Headers and Libraries

- Create `libinput-macos-stubs/` directory
- Add stub `.pc` files for each missing library
- Add stub headers with minimal definitions
- Implement no-op functions or return errors

### 3. Patch Source Files

- Replace `#include <linux/input.h>` with conditional includes
- Guard Linux-specific code with `#ifndef __APPLE__`
- Add macOS compatibility code where needed

### 4. Patch Build Files

- Make dependencies optional in `meson.build`
- Add include directories for stubs
- Configure build options for macOS

### 5. Test and Iterate

- Build incrementally, fixing errors one at a time
- Test functionality that doesn't require Linux-specific features
- Document any limitations

## Example: Porting Weston Compositor

The Weston compositor port to macOS demonstrates many of these techniques:

1. **Stub Libraries**: Created stubs for `libevdev`, `libdrm`, `libudev`, `hwdata`
2. **Input Compatibility**: Created `linux-input-compat.h` for input event handling
3. **Build Configuration**: Patched `meson.build` to make dependencies optional
4. **DMA-BUF**: Guarded DMA-BUF code with `#ifndef __APPLE__`
5. **Clock Compatibility**: Defined `CLOCK_MONOTONIC_COARSE` fallback
6. **Input Event Redefinition**: Guarded compatibility header to avoid conflicts with libinput's own input.h
7. **itimerspec Compatibility**: Added macOS definition for `struct itimerspec`
8. **Runtime Library Paths**: Fixed library loading by copying libinput to install directory and updating rpaths

### Key Findings from Weston Port

- **Include Order Matters**: Files that include `libinput.h` should NOT include `linux-input-compat.h` since libinput provides its own input.h
- **Guard Definitions**: Always guard compatibility definitions with preprocessor checks to avoid redefinition errors
- **Runtime Dependencies**: Locally built libraries need to be copied to install directory and rpaths need to be updated using `install_name_tool`
- **Versioned Libraries**: macOS binaries expect specific versioned library names (e.g., `liblibinput.10.dylib`), create symlinks as needed
- **RPATH Strategy**: Use `@loader_path` or `@executable_path` for relative paths, or absolute paths for system-wide installs
- **itimerspec Definition**: Use `timerfd-compat.h` or define `struct itimerspec` in headers that need it, guard with `#ifndef _STRUCT_ITIMERSPEC`
- **Automatic Patching**: Use build scripts to automatically patch source files for macOS compatibility
- **Warnings as Errors**: Enable `-Werror` to catch all issues during porting

### Common Compilation Errors and Fixes

1. **`redefinition of 'input_event'`**: Guard compatibility header with `#ifndef _UAPI_INPUT_H`
2. **`redefinition of 'itimerspec'`**: Use `timerfd-compat.h` or guard with `#ifndef _STRUCT_ITIMERSPEC`
3. **`declaration will not be visible outside`**: Ensure full type definitions are included before function declarations
4. **`unused variable`**: Mark with `__attribute__((unused))` or remove if truly unused
5. **`Library not loaded: @rpath/liblibinput.10.dylib`**: Copy library to install directory, create symlinks, and update rpaths

See `scripts/build-weston-compositor.sh` for a complete example.

## Common Patterns

### Pattern 1: Conditional Includes

```c
#ifdef __APPLE__
#include "compatibility-header.h"
#else
#include <linux/original-header.h>
#endif
```

### Pattern 2: Stub Functions

```c
#ifdef __APPLE__
int linux_specific_function(int arg) {
    // Return error or no-op
    return -1;
}
#else
// Use real Linux function
#endif
```

### Pattern 3: Feature Guards

```c
#ifndef __APPLE__
// Linux-specific code
#else
// macOS alternative or stub
#endif
```

## Tools and Utilities

### Compatibility Headers

- `linux-input-compat.h` - Input event handling
- `linux-dma-buf-compat.h` - Buffer sharing (if needed)
- `pty-compat.h` - Process management

### Build Scripts

- `build-weston-compositor.sh` - Example build script with patching
- Automate dependency detection and patching

### Testing

- Test nested compositor functionality
- Verify input handling works
- Check rendering pipeline

## Runtime Library Issues

### Problem: Missing Dynamic Libraries

When using locally built libraries (like libinput), the runtime linker may not find them. On macOS, libraries are referenced via `@rpath` or absolute paths.

### Solution: Copy Libraries and Update RPATH

```bash
# Copy library to install directory
cp "$LIBINPUT_BUILD_DIR/liblibinput.dylib" "$INSTALL_PREFIX/lib/"

# Create versioned symlinks (binaries may expect specific versions)
ln -sf "liblibinput.dylib" "$INSTALL_PREFIX/lib/liblibinput.10.dylib"

# Update rpath in installed binaries to use @loader_path or @executable_path
install_name_tool -add_rpath "@loader_path/../lib" "$INSTALL_PREFIX/bin/weston"
install_name_tool -add_rpath "@executable_path/../lib" "$INSTALL_PREFIX/bin/weston"

# Update install names to use @rpath instead of absolute paths
install_name_tool -change "/absolute/path/liblibinput.10.dylib" "@rpath/liblibinput.10.dylib" "$INSTALL_PREFIX/bin/weston"
```

**Key Points**:
- Use `@loader_path` or `@executable_path` for relative rpaths
- Create versioned symlinks matching what binaries expect
- Update install names to use `@rpath` for portability

## Limitations

Some features may not be fully portable:

1. **Direct hardware access** - Requires macOS-specific APIs (Metal, IOKit)
2. **Kernel interfaces** - DMA-BUF, evdev require alternative implementations
3. **System integration** - Logind, systemd features unavailable
4. **Performance** - Some optimizations may be Linux-specific
5. **Timer functions** - `timerfd` and related functions are Linux-specific

## Resources

- [Wayland Protocol Specification](https://wayland.freedesktop.org/docs/html/)
- [Meson Build System](https://mesonbuild.com/)
- [macOS System Programming](https://developer.apple.com/documentation/)
- [Wawona Project](https://github.com/your-repo/wawona) - Reference implementation

## Contributing

When porting new Wayland applications:

1. Document all patches and changes
2. Create reusable compatibility headers
3. Update build scripts to handle new dependencies
4. Test thoroughly on macOS
5. Submit patches upstream when possible

## See Also

- `docs/EGL_ON_MACOS.md` - EGL support on macOS
- `scripts/build-weston-compositor.sh` - Complete porting example
- `libinput-macos-stubs/` - Reference stub implementations

