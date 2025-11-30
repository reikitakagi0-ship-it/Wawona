# 📦 Wawona Dependencies & Setup Guide

Complete guide to all dependencies and setup required to build and run Wawona on macOS and iOS.

---

## 🎯 Overview

This guide covers:
- **Build dependencies** (compilers, build tools)
- **Runtime dependencies** (libraries, frameworks)
- **Dependency management** (cloned repositories with iOS/macOS conditionals)
- **macOS-specific setup** (Launchd service configuration)
- **iOS-specific setup** (Simulator and device builds)
- **Verification steps** (how to check everything works)

---

## 📁 Repository Structure

All dependencies are maintained as **forks** in the `dependencies/` directory:

```
Wawona/
├── dependencies/          # All dependency repositories (cloned forks)
│   ├── wayland/          # Wayland protocol library
│   ├── waypipe/          # Wayland forwarding tool
│   ├── kosmickrisp/      # Mesa-based Vulkan driver
│   ├── pixman/           # Pixel manipulation library
│   ├── libffi/           # Foreign function interface
│   ├── libinput/         # Input device handling
│   ├── lz4/              # LZ4 compression
│   ├── zstd/             # ZSTD compression
│   ├── epoll-shim/       # Linux epoll compatibility
│   ├── xkbcommon/        # Keyboard handling
│   ├── weston/           # Reference compositor
│   ├── wayland-protocols/# Wayland protocol definitions
│   └── libinput-macos-stubs/ # macOS compatibility stubs
├── scripts/              # Build and installation scripts
│   ├── install-*-ios.sh  # iOS cross-compilation scripts
│   └── build-*.sh        # Build scripts
├── resources/            # Resource files
│   └── app-bundle/       # Info.plist files for app bundling
├── docs/                 # Documentation
├── tests/                # Test files
└── logs/                 # Build logs
```

---

## 🔧 Build Tools & Prerequisites

### Required System Tools

These come with macOS or Xcode:

- [x] **Xcode Command Line Tools**
  ```bash
  xcode-select --install
  ```
  Verify: `xcode-select -p` should show `/Applications/Xcode.app/Contents/Developer` or `/Library/Developer/CommandLineTools`

- [x] **CMake** (3.20 or later)
  ```bash
  brew install cmake
  ```
  Verify: `cmake --version`

- [x] **Meson** (build system for Wayland, Pixman, etc.)
  ```bash
  brew install meson
  ```
  Verify: `meson --version`

- [x] **Ninja** (build backend)
  ```bash
  brew install ninja
  ```
  Verify: `ninja --version`

- [x] **pkg-config** (for finding libraries)
  ```bash
  brew install pkg-config
  ```
  Verify: `pkg-config --version`

- [x] **Git** (for cloning dependencies)
  ```bash
  # Usually already installed, or:
  brew install git
  ```

### Compiler Requirements

- **Clang** (comes with Xcode)
  - Verify: `clang --version`
  - Must support C11 and Objective-C
  - iOS cross-compilation: `xcrun --sdk iphonesimulator clang --version`

- **Objective-C Runtime** (included with macOS)
  - No installation needed

---

## 📚 Core Dependencies

All dependencies are **cloned and maintained as forks** in `dependencies/` with iOS/macOS conditionals.

### Wayland Libraries

**Location**: `dependencies/wayland/`

**Installation**:
```bash
# Clone Wayland repository
git clone https://gitlab.freedesktop.org/wayland/wayland.git dependencies/wayland

# Build for macOS
cd dependencies/wayland
meson setup build -Ddocumentation=false
meson compile -C build
sudo meson install -C build

# Build for iOS (cross-compilation)
./scripts/install-wayland-ios.sh
```

**What this installs**:
- `libwayland-server` - Server-side Wayland protocol implementation
- `libwayland-client` - Client-side Wayland protocol implementation
- `wayland-scanner` - Tool to generate protocol bindings from XML
- Headers in `ios-install/include/wayland/` (iOS) or system prefix (macOS)

**iOS Compatibility**:
- Includes `ios_compat.h` for missing Linux functions (`accept4`, `memfd_create`, etc.)
- Provides compatibility headers for `sys/prctl.h`, `sys/procctl.h`

**Verify installation**:
```bash
# macOS
pkg-config --modversion wayland-server
pkg-config --modversion wayland-client

# iOS
ls ios-install/lib/libwayland*.dylib
ls ios-install/include/wayland/
```

### Pixman (Pixel Manipulation)

**Location**: `dependencies/pixman/`

**Installation**:
```bash
# Clone Pixman repository
git clone https://gitlab.freedesktop.org/pixman/pixman.git dependencies/pixman

# Build for macOS
brew install pixman  # or build from source

# Build for iOS
./scripts/install-pixman-ios.sh
```

**What this installs**:
- `libpixman-1` - Low-level pixel manipulation library
- Required for buffer operations

**iOS Compatibility**:
- Includes `ios_compat.h` for `feenableexcept`, `getisax` functions
- Fixed Clang attribute compatibility

**Verify installation**:
```bash
pkg-config --modversion pixman-1
```

### KosmicKrisp Vulkan Driver (REQUIRED - Hard Dependency)

**Location**: `dependencies/kosmickrisp/`

**⚠️ CRITICAL**: KosmicKrisp is **required** for:
- DMA-BUF support on macOS
- EGL support (via Zink driver - OpenGL ES → Vulkan)
- Hardware-accelerated rendering
- iOS Vulkan support

**Installation**:
```bash
# Build and install KosmicKrisp (part of Mesa)
make kosmickrisp
```

This will:
1. Clone Mesa repository to `dependencies/kosmickrisp/`
2. Build KosmicKrisp Vulkan driver for macOS
3. Build KosmicKrisp Vulkan driver for iOS
4. Build EGL with Zink driver (OpenGL ES → Vulkan translation)
5. Install Vulkan driver to `/opt/homebrew/lib/libvulkan_kosmickrisp.dylib` (macOS)
6. Install Vulkan driver to `ios-install/lib/libvulkan_kosmickrisp.dylib` (iOS)
7. Install ICD files for both platforms

**iOS Compatibility**:
- Includes `ios_compat.h` for missing Linux functions
- Provides compatibility headers for `sys/prctl.h`, `sys/procctl.h`, `sys/sysmacros.h`, `sys/mkdev.h`
- Implements iOS fallbacks for `getrandom`, `reallocarray`, `qsort_s`, `secure_getenv`, `thrd_create`, `dl_iterate_phdr`

**What this installs**:
- `libvulkan_kosmickrisp.dylib` - Vulkan-to-Metal driver
- Vulkan ICD (Installable Client Driver) configuration
- Provides Vulkan 1.3 conformance on macOS and iOS

**Verify installation**:
```bash
# macOS
ls /opt/homebrew/lib/libvulkan_kosmickrisp.dylib
ls /opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json

# iOS
ls ios-install/lib/libvulkan_kosmickrisp.dylib
ls ios-install/lib/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json
```

**Dependencies** (automatically installed by `make kosmickrisp`):
- LLVM (for shader compilation)
- Python packages: mako, pyyaml, setuptools
- libclc (OpenCL C library)
- SPIRV-LLVM-Translator

### Waypipe (Wayland Forwarding)

**Location**: `dependencies/waypipe/`

**Installation**:
```bash
# Build waypipe (Rust-based Wayland forwarding)
make waypipe
```

This will:
1. Clone waypipe repository to `dependencies/waypipe/`
2. Build waypipe from source (Rust)
3. Enable `dmabuf`, `video`, `lz4`, `zstd` features
4. Install to `/opt/homebrew/bin/waypipe` (macOS)
5. Install to `ios-install/bin/waypipe` (iOS)

**What this provides**:
- Wayland protocol forwarding over network/sockets
- DMA-BUF support via Vulkan/KosmicKrisp
- Video encoding/decoding support
- Compression (LZ4, ZSTD)

**Verify installation**:
```bash
# macOS
waypipe --version
# Should show: lz4=true, zstd=true, dmabuf=true, video=true

# iOS
ios-install/bin/waypipe --version
```

**Dependencies** (automatically checked by `make waypipe`):
- Rust toolchain (rustc, cargo)
- Vulkan SDK headers (for video feature)
- glslc or glslangValidator (for shader compilation)
- KosmicKrisp Vulkan driver (hard dependency)

### libffi (Foreign Function Interface)

**Location**: `dependencies/libffi/`

**Installation**:
```bash
# Build for iOS
./scripts/install-libffi-ios.sh
```

**What this provides**:
- Foreign function interface library
- Required by Wayland for dynamic function calls

### libinput (Input Device Handling)

**Location**: `dependencies/libinput/`

**Installation**:
```bash
# Build for macOS
make libinput

# iOS support via compatibility stubs
```

**What this provides**:
- Input device handling (Linux-specific)
- macOS compatibility stubs in `dependencies/libinput-macos-stubs/`

### Compression Libraries

**LZ4** (`dependencies/lz4/`):
```bash
./scripts/install-lz4-ios.sh
```

**ZSTD** (`dependencies/zstd/`):
```bash
./scripts/install-zstd-ios.sh
```

Both provide compression support for Waypipe.

### epoll-shim (Linux epoll Compatibility)

**Location**: `dependencies/epoll-shim/`

**Installation**:
```bash
./scripts/install-epoll-shim-ios.sh
```

**What this provides**:
- Linux `epoll` API compatibility for macOS/iOS
- Required by Wayland for event handling

### xkbcommon (Keyboard Handling)

**Location**: `dependencies/xkbcommon/`

**Installation**:
```bash
make xkbcommon
```

**What this provides**:
- Keyboard layout/mapping
- Required for keyboard input handling

### Weston (Reference Compositor)

**Location**: `dependencies/weston/`

**Installation**:
```bash
make weston
```

**What this provides**:
- Reference Wayland compositor implementation
- Useful for testing and comparison
- Runs nested within Wawona

---

## 🍎 macOS Frameworks (Built-in)

These come with macOS - **no installation needed**:

### Core Frameworks:

- **Cocoa** (`-framework Cocoa`)
  - NSWindow, NSApplication, NSEvent
  - Foundation for macOS GUI

- **QuartzCore** (`-framework QuartzCore`)
  - CALayer, CAAnimation
  - Core Animation for rendering

- **CoreVideo** (`-framework CoreVideo`)
  - CVDisplayLink (alternative to CADisplayLink)
  - Video timing and display management

- **IOKit** (`-framework IOKit`)
  - Device access (if needed for input)
  - Usually accessed via Cocoa/NSEvent

- **CoreGraphics** (`-framework CoreGraphics`)
  - CGImage, CGColor, CGContext
  - Graphics primitives

- **AppKit** (`-framework AppKit`)
  - Part of Cocoa, but can be explicitly linked
  - macOS UI framework

---

## 📋 Complete Installation Script

Here's a one-liner to install **everything**:

```bash
# Install build tools (via Homebrew)
brew install cmake pkg-config pixman meson ninja expat libffi libxml2

# Clone all dependencies (they will be built as needed)
make ios-wayland    # Build Wayland for iOS
make kosmickrisp    # Build KosmicKrisp for macOS and iOS
make waypipe        # Build Waypipe for macOS and iOS
```

### Verify All Dependencies:

```bash
#!/bin/bash
echo "Checking dependencies..."

echo -n "CMake: "
cmake --version | head -n1

echo -n "pkg-config: "
pkg-config --version

echo -n "wayland-server: "
pkg-config --modversion wayland-server 2>/dev/null || echo "NOT FOUND"

echo -n "pixman: "
pkg-config --modversion pixman-1 2>/dev/null || echo "NOT FOUND"

echo -n "KosmicKrisp Vulkan driver (macOS): "
test -f /opt/homebrew/lib/libvulkan_kosmickrisp.dylib && echo "OK" || echo "NOT FOUND"

echo -n "KosmicKrisp Vulkan driver (iOS): "
test -f ios-install/lib/libvulkan_kosmickrisp.dylib && echo "OK" || echo "NOT FOUND"

echo -n "waypipe (macOS): "
test -f /opt/homebrew/bin/waypipe && waypipe --version 2>/dev/null | head -1 || echo "NOT FOUND"

echo -n "waypipe (iOS): "
test -f ios-install/bin/waypipe && ios-install/bin/waypipe --version 2>/dev/null | head -1 || echo "NOT FOUND"

echo -n "Cocoa framework: "
test -d /System/Library/Frameworks/Cocoa.framework && echo "OK" || echo "NOT FOUND"

echo "Done!"
```

Save as `scripts/check-deps.sh`, make executable: `chmod +x scripts/check-deps.sh`, run: `./scripts/check-deps.sh`

---

## 🔄 Dependency Fork Management

All dependencies are maintained as **forks** with iOS/macOS conditionals:

### Fork Strategy

1. **Clone upstream repositories** into `dependencies/`
2. **Add iOS compatibility layers**:
   - `ios_compat.h` - Function compatibility shims
   - `ios_sys_headers.h` - System header compatibility
   - Conditional compilation flags for iOS vs macOS

3. **Maintain compatibility**:
   - Keep forks in sync with upstream
   - Add iOS-specific patches as needed
   - Document all modifications

### Adding iOS Support to a Dependency

1. **Clone the repository**:
   ```bash
   git clone <upstream-url> dependencies/<dependency-name>
   ```

2. **Create iOS compatibility header**:
   ```c
   // dependencies/<dependency>/ios_compat.h
   #ifdef __APPLE__
   // iOS compatibility implementations
   #endif
   ```

3. **Update build system**:
   - Add iOS cross-compilation support
   - Include compatibility headers
   - Add conditional compilation flags

4. **Create installation script**:
   ```bash
   # scripts/install-<dependency>-ios.sh
   # Cross-compile for iOS Simulator
   ```

5. **Update Makefile**:
   - Add build targets
   - Reference new script paths

---

## 🚀 Launchd Service Setup (macOS)

Since you want to use **macOS Launchd** (not systemd), here's how to set up the compositor as a service.

### Option 1: User Agent (Recommended)

Runs as your user, starts on login.

**Create**: `~/Library/LaunchAgents/com.aspauldingcode.wawona.compositor.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aspauldingcode.wawona.compositor</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/your/build/Wawona</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/tmp/wawona.log</string>
    
    <key>StandardErrorPath</key>
    <string>/tmp/wawona.error.log</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>WAYLAND_DISPLAY</key>
        <string>wayland-0</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
```

**Load the service**:
```bash
launchctl load ~/Library/LaunchAgents/com.aspauldingcode.wawona.compositor.plist
```

---

## 🔍 Dependency Verification Checklist

Use this checklist to verify everything is installed:

- [ ] Xcode Command Line Tools installed
- [ ] CMake installed and in PATH
- [ ] Meson and Ninja installed
- [ ] pkg-config installed
- [ ] wayland-server library found (macOS)
- [ ] wayland libraries found (iOS: `ios-install/lib/`)
- [ ] pixman library found
- [ ] KosmicKrisp Vulkan driver installed (macOS and iOS)
- [ ] waypipe installed (macOS and iOS)
- [ ] Cocoa framework available
- [ ] QuartzCore framework available
- [ ] CoreVideo framework available
- [ ] Build succeeds (`cmake .. && make`)
- [ ] Compositor runs (`./Wawona`)
- [ ] Wayland socket created (`ls /tmp/wayland-*`)
- [ ] iOS build succeeds (`make ios-build-compositor`)

---

## 🐛 Troubleshooting

### "Library not found" errors

**Problem**: Linker can't find libraries

**Solution**:
```bash
# Check library paths
echo $DYLD_LIBRARY_PATH
pkg-config --libs wayland-server

# Add to CMakeLists.txt or set environment:
export DYLD_LIBRARY_PATH=/opt/homebrew/lib:$DYLD_LIBRARY_PATH
```

### "Header not found" errors

**Problem**: Compiler can't find headers

**Solution**:
```bash
# Check include paths
pkg-config --cflags wayland-server

# Verify headers exist:
ls /opt/homebrew/include/wayland/wayland-server.h
ls ios-install/include/wayland/wayland-server.h
```

### iOS build failures

**Problem**: iOS cross-compilation fails

**Solution**:
```bash
# Check iOS SDK
xcrun --sdk iphonesimulator --show-sdk-path

# Verify cross-compilation tools
xcrun --sdk iphonesimulator clang --version

# Check dependency installation
ls ios-install/lib/
ls ios-install/include/
```

---

## 📝 Next Steps

After installing dependencies:

1. **Build the compositor**:
   ```bash
   mkdir build && cd build
   cmake ..
   make -j8
   ```

2. **Build for iOS**:
   ```bash
   make ios-build-compositor
   ```

3. **Test manually**:
   ```bash
   ./Wawona
   ```

4. **Set up Launchd** (if desired):
   - Create plist file
   - Load service
   - Verify it's running

---

## 📚 Additional Resources

- **Homebrew**: https://brew.sh
- **Launchd Documentation**: `man launchd.plist`
- **Wayland Protocol**: https://wayland.freedesktop.org/docs/html/
- **Mesa/KosmicKrisp**: https://gitlab.freedesktop.org/mesa/mesa
- **Waypipe**: https://gitlab.freedesktop.org/mstoeckl/waypipe

---

_Last updated: November 2024_
