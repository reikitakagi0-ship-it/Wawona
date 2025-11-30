# Platform Stubs

This directory contains minimal stub implementations for platform-specific libraries that don't have full native support.

## Purpose

Stubs provide:
- Minimal API compatibility for libraries that don't fully work on a platform
- Header-only implementations where possible
- Fallback behavior that allows code to compile and run (with limitations)

## Structure

Each stub directory follows this structure:

```
stubs/
└── <library>-<platform>/
    ├── include/          # Stub headers
    ├── src/             # Stub implementations (if needed)
    └── README.md        # Stub-specific documentation
```

## Current Stubs

### libinput-macos

**Purpose**: Provides stub implementations of libinput API for macOS.

**Why**: libinput is Linux-specific and doesn't work natively on macOS. We use macOS native input handling (NSEvent) but some code may expect libinput API.

**Usage**:
```c
#include <libinput.h>
// Use libinput API - stubs will provide minimal compatibility
```

**Limitations**:
- Most functions return errors or no-ops
- Actual input handling uses macOS native APIs
- Only provides API compatibility, not functionality

## Adding New Stubs

1. Create directory: `stubs/<library>-<platform>/`
2. Add headers to `include/`
3. Add implementations to `src/` (if needed)
4. Create `README.md` documenting:
   - Purpose
   - Limitations
   - Usage
   - Integration points

## Integration

Stubs are typically:
- Included via `-I` flags in build system
- Linked before system libraries
- Used conditionally based on platform

Example CMakeLists.txt:
```cmake
if(APPLE)
    include_directories(${CMAKE_SOURCE_DIR}/stubs/libinput-macos/include)
endif()
```

