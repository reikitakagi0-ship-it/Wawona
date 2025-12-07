# Wawona Compositor Dependencies

This document lists all dependencies required to build Wawona Compositor for macOS, iOS, and Android.

## Core Dependencies

These are the essential dependencies required for all platforms:

### Wayland Stack
- **wayland** - Core Wayland protocol library (libwayland-server, libwayland-client)
- **wayland-protocols** - Wayland protocol definitions and extensions
- **waypipe** - Network transparency for Wayland applications

### System Libraries
- **epoll-shim** - epoll compatibility layer for macOS/iOS
- **libffi** - Foreign Function Interface library
- **expat** - XML parsing library
- **libxml2** - XML processing library
- **pixman** - Low-level pixel manipulation library
- **xkbcommon** - Keyboard handling library
- **zlib** - Compression library
- **lz4** - Fast compression library
- **zstd** - Zstandard compression library

### Media & Codecs
- **ffmpeg** - Multimedia framework for audio/video processing

### Graphics & Rendering
- **vulkan-stub** - Vulkan API stubs for platforms without native Vulkan support
- **Angle** (iOS/macOS) - OpenGL ES implementation for Apple platforms

## Platform-Specific Dependencies

### macOS
- Apple Frameworks:
  - Foundation
  - AppKit
  - QuartzCore
  - CoreVideo
  - CoreMedia
  - CoreGraphics
  - Metal
  - MetalKit
  - IOSurface
  - VideoToolbox
  - AVFoundation

### iOS
- Apple Frameworks:
  - Foundation
  - UIKit
  - QuartzCore
  - CoreVideo
  - CoreMedia
  - CoreGraphics
  - Metal
  - MetalKit
  - IOSurface
  - VideoToolbox
  - AVFoundation

### Android
- Android NDK
- EGL (via Android system libraries)
- Vulkan (via Android system libraries)

## Build Tools

### Required Build Tools
- **cmake** (3.20+) - Build system
- **meson** - Build system for some dependencies
- **ninja** - Build tool
- **pkg-config** - Package configuration tool
- **autotools** (autoconf, automake, libtool) - For some dependencies

### Host Tools (for cross-compilation)
- **host-cmake** - CMake for the build host
- **host-pkg-config** - pkg-config for the build host
- **host-autotools** - Autotools for the build host

## Wayland & Waypipe Dependencies

### Wayland Core Dependencies
- **libffi** - Required for Wayland's dynamic binding
- **expat** - XML parsing for protocol definitions
- **pixman** - Pixel manipulation for Wayland buffers

### Waypipe Dependencies
- **wayland-client** - Wayland client library (for waypipe client)
- **wayland-server** - Wayland server library (for waypipe server)
- **zlib** - Compression for network transport
- **lz4** - Fast compression (optional, for better performance)
- **zstd** - Zstandard compression (optional, for better performance)

### Waypipe-rs (Rust Implementation)
If using waypipe-rs instead of the C implementation:
- **Rust toolchain** (rustc, cargo)
- **wayland-client** (Rust bindings)
- **wayland-server** (Rust bindings)
- Compression libraries (zlib, lz4, zstd) via Rust crates

## Dependency Build Order

For a clean build, dependencies should be built in this order:

1. **Host tools** (cmake, pkg-config, autotools)
2. **System compatibility** (epoll-shim, libffi)
3. **Core libraries** (expat, libxml2, zlib, lz4, zstd)
4. **Wayland stack** (wayland, wayland-protocols)
5. **Graphics** (pixman, xkbcommon)
6. **Media** (ffmpeg)
7. **Rendering** (vulkan-stub, Angle framework)
8. **Network transparency** (waypipe)

## Notes

- All dependencies are built from source for App Store compliance
- Dependencies are statically linked where possible
- Patches may be applied to dependencies for platform compatibility (see `scripts/patches/`)
- iOS dependencies are cross-compiled using a custom toolchain
- Android dependencies use the Android NDK toolchain
