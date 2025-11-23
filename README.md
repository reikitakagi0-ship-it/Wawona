# Wawona

[![Build Status](https://github.com/YOUR_USERNAME/Wawona/actions/workflows/build.yml/badge.svg)](https://github.com/YOUR_USERNAME/Wawona/actions/workflows/build.yml)
[![Protocol Status](https://github.com/YOUR_USERNAME/Wawona/actions/workflows/protocols.yml/badge.svg)](https://github.com/YOUR_USERNAME/Wawona/actions/workflows/protocols.yml)
[![Code Style](https://img.shields.io/badge/code%20style-clang--format-blue)](https://clang.llvm.org/docs/ClangFormat.html)

<div align="center">
  <img src="preview1.png" alt="Wawona - Wayland Compositor for macOS Preview" width="800"/>
  
  <details>
    <summary><b>See More</b></summary>
    <br>
    <img src="preview2.png" alt="Wawona - Wayland Compositor for macOS Preview 2" width="800"/>
    <br><br>
    <img src="preview3.png" alt="Wawona - Wayland Compositor for macOS Preview 3" width="800"/>
  </details>
</div>

**Wawona** is a Wayland Compositor for macOS. A **from-scratch** native macOS Wayland compositor with a full Cocoa compatibility layer, built with libwayland-server and Metal for desktop shells and compositors.

## Support

If you find Wawona useful, consider supporting the project:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/aspauldingcode)

## Overview

This compositor runs **natively on macOS** - no Linux, VM, or container required. It features:
- **libwayland-server** (core C API) for protocol marshaling
- **Metal** for high-performance rendering of desktop shells and compositors
- **Cocoa compatibility layer** providing full integration with macOS windowing and input systems
- **NSWindow** for native compositor window management
- **Custom compositor implementation** (not WLRoots - we build our own)
- **Full Wayland protocol support** for QtWayland and other Wayland clients

**Important**: This is a from-scratch compositor implementation with a complete Cocoa compatibility layer. We use ONLY the core Wayland protocol library (`libwayland-server`) for protocol handling, and implement all compositor logic ourselves using Metal for rendering and Cocoa for system integration.

## Prerequisites

See **[docs/DEPENDENCIES.md](docs/DEPENDENCIES.md)** for complete dependency information.

Quick install:

```bash
# Build tools
brew install cmake pkg-config pixman

# Wayland - Homebrew won't install it (Linux requirement), so build from source:
brew install meson ninja expat libffi libxml2
git clone https://gitlab.freedesktop.org/wayland/wayland.git
cd wayland
meson setup build -Ddocumentation=false
meson compile -C build
sudo meson install -C build

# KosmicKrisp Vulkan driver (REQUIRED for DMA-BUF support)
make kosmickrisp

# Waypipe (for Wayland forwarding)
make waypipe
```

**Note**: We do NOT use `wlroots` - it's Linux-only. We're building our own compositor.

Verify installation:

```bash
./check-deps.sh
```

## Quick Start

### macOS Setup

**Step-by-step build order:**

1. **Install build tools**:
   ```bash
   brew install cmake pkg-config meson ninja expat libffi libxml2 pixman
   ```

2. **Build Wayland** (core protocol libraries):
   ```bash
   make wayland
   ```
   This builds Wayland for macOS and installs to `/opt/homebrew/`.

3. **Build KosmicKrisp Vulkan driver** (required for DMA-BUF and EGL support):
   ```bash
   make kosmickrisp
   ```
   This builds KosmicKrisp for **both macOS and iOS**:
   - macOS: Installs to `/opt/homebrew/lib/`
   - iOS: Installs to `ios-install/lib/`
   
   **Note**: KosmicKrisp is required for:
   - DMA-BUF support (zero-copy buffers)
   - EGL/OpenGL ES support (via Zink driver)
   - Hardware-accelerated rendering

4. **Build Waypipe** (for Wayland forwarding over network):
   ```bash
   make waypipe
   ```
   This builds Waypipe for **both macOS and iOS**:
   - macOS: Installs to `/opt/homebrew/bin/waypipe`
   - iOS: Installs to `ios-install/bin/waypipe`
   
   **Note**: Requires KosmicKrisp to be installed first (for dmabuf/video features).

5. **Build and run compositor**:
   ```bash
   # Build compositor
   make compositor
   
   # Run compositor (in one terminal)
   make run-compositor
   
   # Run test client (in another terminal)
   make run-client
   ```

**Quick one-liner** (builds everything):
```bash
make wayland && make kosmickrisp && make waypipe && make compositor
```

### iOS Simulator Setup

**Prerequisites:**
- Xcode installed with iOS Simulator SDK
- Xcode command-line tools: `xcode-select --install`
- Rust toolchain via rustup (for Waypipe): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

**Step-by-step build order:**

1. **Build iOS dependencies** (all at once):
   ```bash
   make ios-compositor
   ```
   This automatically builds:
   - Wayland for iOS (`ios-wayland`)
   - KosmicKrisp for iOS (`ios-kosmickrisp`)
   - Waypipe for iOS (`ios-waypipe`)
   - Wawona compositor for iOS
   - Installs and launches in iOS Simulator

2. **Or build dependencies individually**:
   ```bash
   # Build Wayland for iOS
   make ios-wayland
   
   # Build KosmicKrisp for iOS (requires ios-wayland)
   make ios-kosmickrisp
   
   # Build Waypipe for iOS (requires ios-wayland, ios-kosmickrisp)
   make ios-waypipe
   
   # Build Wawona compositor for iOS
   make ios-build-compositor
   
   # Install and run in iOS Simulator
   make ios-install-compositor
   make ios-run-compositor
   ```

3. **Connect to iOS Simulator compositor**:
   ```bash
   # In one terminal: iOS compositor should be running
   # In another terminal: Connect via waypipe
   make colima-client-ios
   ```
   This runs Weston in a Docker container and connects to the iOS Simulator Wayland socket.

**Note**: The iOS build process:
- Cross-compiles all dependencies for iOS Simulator (arm64)
- Creates an iOS app bundle with proper Info.plist
- Code signs for iOS Simulator
- Launches automatically in the iOS Simulator

### Platform-Specific Targets

If you only want to build for one platform:

**macOS only:**
```bash
make kosmickrisp-macos  # Build KosmicKrisp for macOS only
```

**iOS only:**
```bash
make ios-wayland        # Build Wayland for iOS only
make ios-kosmickrisp    # Build KosmicKrisp for iOS only
make ios-waypipe        # Build Waypipe for iOS only
```

**Both platforms** (default):
```bash
make kosmickrisp        # Builds for both macOS and iOS
make waypipe            # Builds for both macOS and iOS
```

### Manual Setup (Alternative)

If you prefer manual setup instead of using the Makefile:

1. **Install dependencies**:
   ```bash
   # Build tools
   brew install cmake pkg-config pixman meson ninja expat libffi libxml2
   
   # Wayland - Homebrew won't install it (Linux requirement), build from source:
   git clone https://gitlab.freedesktop.org/wayland/wayland.git
   cd wayland
   meson setup build -Ddocumentation=false
   meson compile -C build
   sudo meson install -C build
   ```
   
   **Note**: `wayland` provides ONLY the core protocol libraries (libwayland-server/client). No compositor, no backends, no rendering - just protocol marshaling. We implement everything else ourselves.

2. **Verify dependencies**:
   ```bash
   ./check-deps.sh
   ```

3. **Build compositor**:
   ```bash
   mkdir build && cd build
   cmake ..
   make -j8
   ```

4. **Run compositor**:
   ```bash
   ./Wawona
   ```

5. **View docs** (in another terminal):
   ```bash
   ./serve-docs.sh
   ```

## Building

```bash
mkdir build
cd build
cmake ..
make -j8
```

## Running

```bash
./Wawona
```

The compositor will:
1. Open an NSWindow titled "Wawona"
2. Create a Wayland socket (typically `wayland-0`)
3. Print the WAYLAND_DISPLAY name to the console

## Viewing Documentation

The documentation is now in the `docs/` folder with a proper Node.js server.

**First time setup** (installs npm dependencies):

```bash
./serve-docs.sh
```

This will:
1. Install npm dependencies (express, marked) if needed
2. Start the documentation server
3. Automatically open your browser to http://localhost:8080

Or specify a custom port:

```bash
./serve-docs.sh 3000
```

**Manual setup** (if you prefer):

```bash
cd docs
npm install
npm start
```

The server uses Express.js to serve markdown files with proper rendering via the marked library.

## Testing with Wayland Clients

### Build Test Clients

Wawona includes a comprehensive test client suite for compositor development:

```bash
# Build all test clients
make test-clients-build

# Or build individual categories
make test-clients-minimal    # Minimal clients (fast)
make test-clients-weston      # Weston demo clients (comprehensive)
make test-clients-debug       # Debugging tools
make test-clients-nested      # Nested compositor scripts
```

See **[TEST_CLIENTS_QUICKSTART.md](TEST_CLIENTS_QUICKSTART.md)** for complete guide.

### Run Test Suite

```bash
# Start compositor (in one terminal)
make run-compositor

# Run all tests (in another terminal)
make test-clients-run
```

### Individual Test Clients

```bash
export WAYLAND_DISPLAY=wayland-0

# Basic tests
./test-clients/bin/simple-shm
./test-clients/bin/simple-damage

# Weston demo clients
./test-clients/bin/weston-simple-shm
./test-clients/bin/weston-subsurfaces
./test-clients/bin/weston-eventdemo

# Debugging tools
./test-clients/bin/wayland-info
```

### Local Clients

Once the compositor is running, set the WAYLAND_DISPLAY environment variable and run a Wayland client:

```bash
export WAYLAND_DISPLAY=wayland-0
./MyQtApp -platform wayland
```

### Test Color Client

Test color management features (HDR, ICC profiles, color spaces):

```bash
# Build compositor and test client
make compositor
make client

# Run compositor (in one terminal)
./Wawona

# Run color test client (in another terminal)
export WAYLAND_DISPLAY=wayland-0
./test_color_client
```

The test client will:
- Test sRGB color space
- Test DCI-P3 color space
- Test HDR support
- Test ICC profile handling
- Animate color transitions
- Log all operations to stdout

### Running Linux Clients in Docker (Colima)

Run Linux Wayland clients (like Weston) in a Docker container with full DMA-BUF and video support:

```bash
# Start compositor (in one terminal)
make run-compositor

# Run Weston in Docker container via waypipe (in another terminal)
make colima-client
```

This will:
1. Start waypipe client to proxy the compositor connection
2. Start a Docker container with Weston
3. Install Mesa Vulkan drivers in the container
4. Forward Wayland protocol via waypipe with DMA-BUF support

**Requirements**:
- Colima installed (`brew install colima`)
- KosmicKrisp Vulkan driver installed (`make kosmickrisp`)
- Waypipe built (`make waypipe`)

## Current Status

This compositor is **fully functional** with:
- ✅ Metal-based rendering pipeline for desktop shells and compositors
- ✅ Complete Cocoa compatibility layer for macOS integration
- ✅ Full Wayland protocol support (xdg-shell, input, output, etc.)
- ✅ Buffer handling (SHM and DMA-BUF via Vulkan/KosmicKrisp)
- ✅ Input event processing (keyboard, mouse, touch)
- ✅ Native macOS window management
- ✅ **Color Management Protocol** (`color-management-v1`) - HDR, ICC profiles, color space support
- ✅ **Presentation Time Protocol** (`presentation-time`) - Frame timing and synchronization
- ✅ **Thread-safe surface management** - Proper synchronization for multi-threaded rendering
- ✅ **Frame callback improvements** - Reliable animation and frame synchronization
- ✅ **KosmicKrisp Vulkan driver** - Vulkan 1.3 conformance on macOS (required for DMA-BUF)
- ✅ **Waypipe integration** - Rust-based Wayland forwarding with video + DMA-BUF support
- ✅ **Colima client support** - Run Linux Wayland clients in Docker containers via waypipe

## Architecture

```
macOS app
→ creates NSWindow with Cocoa compatibility layer
→ initializes libwayland-server (protocol marshaling ONLY)
→ implements custom compositor logic in Objective-C
→ Metal renderer for desktop shells and compositors
→ exposes WAYLAND_DISPLAY=wayland-0
→ Wayland clients connect (QtWayland, GTK, etc.)
→ compositor receives buffers (SHM, DMA-BUF)
→ Metal-based rendering pipeline
→ Cocoa integration for windowing and input
```

### What We Implement Ourselves:
- ✅ Compositor core logic
- ✅ Cocoa compatibility layer for macOS integration
- ✅ Metal renderer for desktop shells and compositors
- ✅ Output (wl_output) implementation
- ✅ Surface (wl_surface) management with thread-safe access
- ✅ Buffer handling (SHM, DMA-BUF → Metal textures)
- ✅ Input event bridging (NSEvent → Wayland events)
- ✅ xdg-shell protocol (for window management)
- ✅ Frame timing and synchronization (presentation-time protocol)
- ✅ Color management (color-management-v1 protocol) - HDR, ICC profiles, color spaces

### What We Use From Libraries:
- ✅ `libwayland-server`: Protocol marshaling/unmarshaling
- ✅ `wayland-scanner`: XML → C header generation
- ✅ macOS frameworks: Cocoa, Metal, QuartzCore, CoreVideo

## Running as a Service (Launchd)

To run the compositor as a macOS Launchd service:

1. Copy `com.aspauldingcode.wawona.compositor.plist` to `~/Library/LaunchAgents/`
2. Update the `ProgramArguments` path to your compositor binary
3. Load the service:
   ```bash
   launchctl load ~/Library/LaunchAgents/com.aspauldingcode.wawona.compositor.plist
   ```

See **[DEPENDENCIES.md](DEPENDENCIES.md)** for detailed Launchd setup instructions.

## Recent Improvements

### Thread Safety & Stability
- ✅ Thread-safe surface list management with pthread mutex
- ✅ Race condition fixes for frame callbacks and buffer operations
- ✅ Comprehensive resource validation before sending Wayland events
- ✅ Safe client disconnect handling to prevent crashes

### Color Management
- ✅ Full `color-management-v1` protocol implementation
- ✅ Support for ICC profiles (v2 and v4)
- ✅ Parametric color space descriptions
- ✅ HDR support (Windows scRGB, extended sRGB)
- ✅ Color space detection and conversion
- ✅ Test client for validating color operations

### Frame Synchronization
- ✅ `presentation-time` protocol for accurate frame timing
- ✅ Improved frame callback handling with immediate sends
- ✅ Proper frame synchronization at display refresh rate (60Hz)
- ✅ Reliable animation support for clients

## Notes

- This is a **from-scratch compositor implementation** with a complete Cocoa compatibility layer
- We do NOT use WLRoots (it's Linux-only and cannot run on macOS)
- We use ONLY `libwayland-server` for protocol handling
- **Metal** is used for high-performance rendering of desktop shells and compositors
- All compositor logic, rendering, and input is implemented in Objective-C with Metal shaders
- Full Cocoa integration for native macOS windowing and input systems
- No DRM, GBM, libinput, or udev dependencies
- Runs entirely in userspace on macOS
- Uses macOS Launchd (not systemd) for service management

## Why Not WLRoots?

**WLRoots requires Linux**. Even though Homebrew might let you install it, it:
- Depends on DRM/KMS (Linux kernel display management)
- Depends on libinput (Linux input handling)
- Depends on udev (Linux device management)
- Cannot actually function on macOS

Instead, we build our own compositor using:
- `libwayland-server` (protocol layer only)
- **Metal** for high-performance rendering of desktop shells and compositors
- **Cocoa compatibility layer** for full macOS integration
- NSEvent (macOS input)
- Pure Objective-C implementation with Metal shaders

