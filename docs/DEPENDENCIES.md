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
- **mesa-kosmickrisp** (macOS/iOS) - Vulkan-to-Metal driver built from Mesa source code, compiles as .dylib
- **Freedreno/turnip** (Android) - Vulkan driver for Qualcomm Adreno GPUs
- *(OpenGL support for macOS/iOS is TBD; recommendations welcome)*

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
Waypipe has been rewritten in Rust (version 0.10.0+):
- **Rust toolchain** (rustc, cargo) - Required for building waypipe
- **wayland-client** (Rust bindings) - Wayland client library bindings
- **wayland-server** (Rust bindings) - Wayland server library bindings
- **mesa-kosmickrisp** - Vulkan driver dependency for macOS/iOS Vulkan support
- Compression libraries (zlib, lz4, zstd) via Rust crates

## Dependency Build Order

For a clean build, dependencies should be built in this order:

1. **Host tools** (cmake, pkg-config, autotools)
2. **System compatibility** (epoll-shim, libffi)
3. **Core libraries** (expat, libxml2, zlib, lz4, zstd)
4. **Wayland stack** (wayland, wayland-protocols)
5. **Graphics** (pixman, xkbcommon)
6. **Media** (ffmpeg)
7. **Rendering** (mesa-kosmickrisp Vulkan driver)
8. **Network transparency** (waypipe-rs with KosmicKrisp support)

## Notes

- All dependencies are built from source
- Dependencies are statically linked where possible
- Patches may be applied to dependencies for platform compatibility (see `dependencies/patches/`)
- iOS dependencies are cross-compiled using Nix cross-compilation toolchains
- Android dependencies use the Android NDK toolchain via Nix
- Mesa-KosmicKrisp builds as a .dylib for macOS/iOS
- Waypipe-rs (Rust) requires KosmicKrisp for Vulkan support on macOS/iOS