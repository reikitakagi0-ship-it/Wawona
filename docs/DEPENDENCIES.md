# 📦 Wawona Dependencies & Setup Guide

Complete guide to all dependencies and setup required to build and run Wawona on macOS.

---

## 🎯 Overview

This guide covers:
- **Build dependencies** (compilers, build tools)
- **Runtime dependencies** (libraries, frameworks)
- **macOS-specific setup** (Launchd service configuration)
- **Verification steps** (how to check everything works)

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

- [x] **pkg-config** (for finding libraries)
  ```bash
  brew install pkg-config
  ```
  Verify: `pkg-config --version`

- [x] **Git** (for cloning dependencies if needed)
  ```bash
  # Usually already installed, or:
  brew install git
  ```

### Compiler Requirements

- **Clang** (comes with Xcode)
  - Verify: `clang --version`
  - Must support C11 and Objective-C

- **Objective-C Runtime** (included with macOS)
  - No installation needed

---

## 📚 Core Dependencies

### Wayland Libraries

These are the **essential** Wayland protocol libraries.

**⚠️ Important**: Homebrew's `wayland` formula has `depends_on :linux`, so `brew install wayland` will fail on macOS. However, **Wayland itself is platform-agnostic** and can be built from source on macOS.

**Installation on macOS** (Build from Source):

Since Homebrew won't install it, you must build wayland from source:

```bash
# Install build dependencies
brew install meson ninja pkg-config expat libffi libxml2

# Clone and build wayland
git clone https://gitlab.freedesktop.org/wayland/wayland.git
cd wayland
meson setup build -Ddocumentation=false
meson compile -C build
sudo meson install -C build
```

**What this installs**:
- `libwayland-server` - Server-side Wayland protocol implementation
- `libwayland-client` - Client-side Wayland protocol implementation
- `wayland-scanner` - Tool to generate protocol bindings from XML
- Headers in `/usr/local/include/wayland/` (or custom prefix)

**Verify installation**:
```bash
pkg-config --modversion wayland-server
pkg-config --modversion wayland-client
which wayland-scanner
ls /usr/local/lib/libwayland*  # or your install prefix
```

**Alternative**: If you have a custom install prefix, set `PKG_CONFIG_PATH`:
```bash
export PKG_CONFIG_PATH=/your/prefix/lib/pkgconfig:$PKG_CONFIG_PATH
```

### WLRoots (Compositor Toolkit)

**⚠️ NOT USED**: We do NOT use WLRoots - it's Linux-only and cannot run on macOS. We build our own compositor implementation using only `libwayland-server` and macOS frameworks.

**Why not WLRoots?**:
- Requires DRM/KMS (Linux kernel display management)
- Requires libinput (Linux input handling)
- Requires udev (Linux device management)
- Cannot function on macOS

**Instead**, we implement:
- Compositor logic ourselves in Objective-C
- Rendering using CALayer (macOS native)
- Input handling using NSEvent (macOS native)
- Protocol handling using `libwayland-server` only

### Pixman (Pixel Manipulation)

```bash
brew install pixman
```

**What this installs**:
- `libpixman-1` - Low-level pixel manipulation library
- Required by WLRoots for buffer operations

**Verify installation**:
```bash
pkg-config --modversion pixman-1
```

### KosmicKrisp Vulkan Driver (REQUIRED - Hard Dependency)

**⚠️ CRITICAL**: KosmicKrisp is **required** for:
- DMA-BUF support on macOS
- EGL support (via Zink driver - OpenGL ES → Vulkan)
- Hardware-accelerated rendering

The compositor build will fail if it's not installed.

**Installation**:
```bash
# Build and install KosmicKrisp (part of Mesa)
make kosmickrisp
```

This will:
1. Clone Mesa repository
2. Build KosmicKrisp Vulkan driver for macOS
3. Build EGL with Zink driver (OpenGL ES → Vulkan translation)
4. Install Vulkan driver to `/opt/homebrew/lib/libvulkan_kosmickrisp.dylib`
5. Install EGL libraries (`libEGL.dylib`, `libGLESv2.dylib`)
6. Install ICD file to `/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json`

**EGL Support**: EGL is enabled with Zink driver, which translates OpenGL ES calls to Vulkan. Since KosmicKrisp provides Vulkan support, EGL clients will use hardware-accelerated rendering via Vulkan → Metal.

**What this installs**:
- `libvulkan_kosmickrisp.dylib` - Vulkan-to-Metal driver
- Vulkan ICD (Installable Client Driver) configuration
- Provides Vulkan 1.3 conformance on macOS

**Verify installation**:
```bash
ls /opt/homebrew/lib/libvulkan_kosmickrisp.dylib
ls /opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json
```

**Dependencies** (automatically installed by `make kosmickrisp`):
- LLVM (for shader compilation)
- Python packages: mako, pyyaml, setuptools
- libclc (OpenCL C library)
- SPIRV-LLVM-Translator

### Waypipe (Wayland Forwarding)

**Installation**:
```bash
# Build waypipe (Rust-based Wayland forwarding)
make waypipe
```

This will:
1. Build waypipe from source (Rust)
2. Enable `dmabuf`, `video`, `lz4`, `zstd` features
3. Install to `waypipe/target/release/waypipe`

**What this provides**:
- Wayland protocol forwarding over network/sockets
- DMA-BUF support via Vulkan/KosmicKrisp
- Video encoding/decoding support
- Compression (LZ4, ZSTD)

**Verify installation**:
```bash
./waypipe/target/release/waypipe --version
# Should show: lz4=true, zstd=true, dmabuf=true, video=true
```

**Dependencies** (automatically checked by `make waypipe`):
- Rust toolchain (rustc, cargo)
- Vulkan SDK headers (for video feature)
- glslc or glslangValidator (for shader compilation)
- KosmicKrisp Vulkan driver (hard dependency)

### Colima (Docker Runtime for macOS)

**Optional but recommended** for running Linux Wayland clients:

```bash
brew install colima
```

**What this provides**:
- Docker runtime for macOS
- VirtioFS support (required for Unix socket forwarding)
- Linux container support

**Usage**:
```bash
# Start Colima
colima start

# Run Linux Wayland client in container
make colima-client
```

---

## 🔗 WLRoots Dependencies (Auto-installed)

When you install `wlroots` via Homebrew, it automatically installs these dependencies:

### Required by WLRoots:

- **libdrm** (Linux Direct Rendering Manager)
  - Note: On macOS, this is a stub/minimal version
  - WLRoots uses it for buffer management abstractions

- **libgbm** (Generic Buffer Management)
  - Note: On macOS, this may be minimal/stub
  - Used for GPU buffer management

- **libinput** (Input Device Handling)
  - Note: On macOS, we'll use NSEvent instead, but WLRoots expects this
  - May be a stub/minimal version

- **libxkbcommon** (Keyboard Handling)
  - Used for keyboard layout/mapping
  - **Important**: We'll need this for keyboard input

- **libxcb** (X11 Protocol)
  - Used by WLRoots for some internal abstractions
  - May be minimal on macOS

- **mesa** (OpenGL/Vulkan)
  - Graphics library
  - On macOS, we'll primarily use Metal/CALayer, but WLRoots may use OpenGL

- **libseat** (Session Management)
  - For seat/session handling
  - May be minimal on macOS

### Optional but Recommended:

- **libudev** (Device Management)
  - Linux device management
  - Not needed on macOS (we use IOKit/NSEvent)

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

### Verify Frameworks Available:

```bash
# Check framework paths
ls /System/Library/Frameworks/Cocoa.framework
ls /System/Library/Frameworks/QuartzCore.framework
ls /System/Library/Frameworks/CoreVideo.framework
```

---

## 🧪 Testing Dependencies (Optional)

### For Testing Wayland Clients:

- **Qt6 with Wayland support** (for testing QtWayland apps)
  ```bash
  brew install qt6
  ```
  Verify: `qmake6 --version`

- **GTK4 with Wayland** (for testing GTK apps)
  ```bash
  brew install gtk4
  ```

- **Weston** (reference compositor, for comparison)
  ```bash
  brew install weston
  ```
  Note: This is optional - mainly for reference/testing

---

## 📋 Complete Installation Script

Here's a one-liner to install **everything**:

```bash
# Install build tools (via Homebrew)
brew install cmake pkg-config pixman meson ninja expat libffi libxml2

# Build wayland from source (Homebrew formula requires Linux)
git clone https://gitlab.freedesktop.org/wayland/wayland.git
cd wayland
meson setup build -Ddocumentation=false
meson compile -C build
sudo meson install -C build

# Optional: Install testing tools
brew install qt6 gtk4
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

echo -n "wlroots: "
pkg-config --modversion wlroots 2>/dev/null || echo "NOT FOUND"

echo -n "pixman: "
pkg-config --modversion pixman-1 2>/dev/null || echo "NOT FOUND"

echo -n "KosmicKrisp Vulkan driver: "
test -f /opt/homebrew/lib/libvulkan_kosmickrisp.dylib && echo "OK" || echo "NOT FOUND"

echo -n "waypipe: "
test -f waypipe/target/release/waypipe && ./waypipe/target/release/waypipe --version 2>/dev/null | head -1 || echo "NOT FOUND"

echo -n "Cocoa framework: "
test -d /System/Library/Frameworks/Cocoa.framework && echo "OK" || echo "NOT FOUND"

echo -n "QuartzCore framework: "
test -d /System/Library/Frameworks/QuartzCore.framework && echo "OK" || echo "NOT FOUND"

echo "Done!"
```

Save as `check-deps.sh`, make executable: `chmod +x check-deps.sh`, run: `./check-deps.sh`

---

## 🚀 Launchd Service Setup

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

**Unload the service**:
```bash
launchctl unload ~/Library/LaunchAgents/com.aspauldingcode.wawona.compositor.plist
```

**Check status**:
```bash
launchctl list | grep wawona
```

### Option 2: System-Wide Daemon

Runs as root, starts on boot (requires admin).

**Create**: `/Library/LaunchDaemons/com.aspauldingcode.wawona.compositor.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aspauldingcode.wawona.compositor</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/Wawona</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/var/log/wawona.log</string>
    
    <key>StandardErrorPath</key>
    <string>/var/log/wawona.error.log</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>WAYLAND_DISPLAY</key>
        <string>wayland-0</string>
    </dict>
    
    <key>UserName</key>
    <string>yourusername</string>
</dict>
</plist>
```

**Load** (requires sudo):
```bash
sudo launchctl load /Library/LaunchDaemons/com.aspauldingcode.wawona.compositor.plist
```

### Launchd Service Management Commands

```bash
# Load service
launchctl load ~/Library/LaunchAgents/com.aspauldingcode.wawona.compositor.plist

# Unload service
launchctl unload ~/Library/LaunchAgents/com.aspauldingcode.wawona.compositor.plist

# Start service (if loaded but not running)
launchctl start com.aspauldingcode.wawona.compositor

# Stop service
launchctl stop com.aspauldingcode.wawona.compositor

# Check if running
launchctl list | grep wawona

# View logs
tail -f /tmp/wawona.log
tail -f /tmp/wawona.error.log
```

### Launchd Plist Keys Explained

- **Label**: Unique identifier for the service
- **ProgramArguments**: Command and arguments to run
- **RunAtLoad**: Start when plist is loaded
- **KeepAlive**: Restart if it crashes
- **StandardOutPath**: Where stdout goes
- **StandardErrorPath**: Where stderr goes
- **EnvironmentVariables**: Environment variables to set
- **UserName**: Run as this user (for LaunchDaemons)

---

## 🔍 Dependency Verification Checklist

Use this checklist to verify everything is installed:

- [ ] Xcode Command Line Tools installed
- [ ] CMake installed and in PATH
- [ ] pkg-config installed
- [ ] wayland-server library found
- [ ] wayland-client library found
- [ ] wlroots library found
- [ ] pixman library found
- [ ] Cocoa framework available
- [ ] QuartzCore framework available
- [ ] CoreVideo framework available
- [ ] Build succeeds (`cmake .. && make`)
- [ ] Compositor runs (`./Wawona`)
- [ ] Wayland socket created (`ls /tmp/wayland-*`)
- [ ] Launchd plist created (if using service)

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
```

### Launchd service won't start

**Problem**: Service fails to launch

**Solution**:
```bash
# Check logs
tail -f /tmp/wawona.error.log

# Check plist syntax
plutil -lint ~/Library/LaunchAgents/com.aspauldingcode.wawona.compositor.plist

# Test manually first
/path/to/Wawona
```

### Wayland socket permissions

**Problem**: Clients can't connect to socket

**Solution**:
```bash
# Check socket permissions
ls -la /tmp/wayland-*

# Should be readable/writable by your user
# If not, check umask and socket creation code
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

2. **Test manually**:
   ```bash
   ./Wawona
   ```

3. **Set up Launchd** (if desired):
   - Create plist file
   - Load service
   - Verify it's running

4. **Test with client**:
   ```bash
   export WAYLAND_DISPLAY=wayland-0
   ./test-client -platform wayland
   ```

---

## 📚 Additional Resources

- **Homebrew**: https://brew.sh
- **Launchd Documentation**: `man launchd.plist`
- **Wayland Protocol**: https://wayland.freedesktop.org/docs/html/
- **WLRoots**: https://gitlab.freedesktop.org/wlroots/wlroots

---

_Last updated: [Date]_

