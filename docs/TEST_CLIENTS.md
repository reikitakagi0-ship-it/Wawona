# Wayland Test Clients for macOS

Complete guide to building and testing Wayland clients on macOS for compositor development.

## Overview

This guide covers building and running essential Wayland test clients on macOS. These clients are critical for verifying compositor protocol compliance, buffer handling, input processing, and overall functionality.

## Quick Start

### Build All Test Clients

```bash
make test-clients-build
```

This will build:
- Minimal test clients (simple-shm, simple-damage)
- Debugging tools (wayland-info, wayland-debug)
- Weston demo clients (weston-simple-shm, weston-simple-egl, etc.)

### Run Tests

```bash
# Start compositor (in one terminal)
make run-compositor

# Run test clients (in another terminal)
make test-clients-run
```

## Categories

### 1. Minimal Test Clients

**Purpose**: Lightweight clients for basic protocol testing

**Build**:
```bash
make test-clients-minimal
```

**Clients**:
- `simple-shm` - Basic SHM buffer test
- `simple-damage` - Damage region testing

**Location**: `test-clients/minimal/bin/`

**Usage**:
```bash
export WAYLAND_DISPLAY=wayland-0
./test-clients/minimal/bin/simple-shm
```

### 2. Weston Demo Clients

**Purpose**: Comprehensive test suite covering all Wayland protocol features

**Build**:
```bash
make test-clients-weston
```

**Clients**:
- `weston-simple-shm` - SHM buffer test
- `weston-simple-egl` - EGL/OpenGL ES test (requires EGL)
- `weston-transformed` - Surface transformations
- `weston-subsurfaces` - Sub-surface hierarchy
- `weston-simple-damage` - Incremental damage
- `weston-simple-touch` - Touch input test
- `weston-eventdemo` - Pointer/keyboard event inspection
- `weston-keyboard` - Keyboard test
- `weston-dnd` - Drag and drop
- `weston-cliptest` - Clipboard test
- `weston-image` - PNG display
- `weston-editor` - Text input protocol test

**Location**: `test-clients/weston/bin/`

**Requirements**:
- Wayland libraries
- Pixman
- EGL (for EGL clients)
- Meson and Ninja

**Usage**:
```bash
export WAYLAND_DISPLAY=wayland-0
./test-clients/weston/bin/weston-simple-shm
```

### 3. Debugging Tools

**Purpose**: Inspect Wayland protocol and debug client connections

**Build**:
```bash
make test-clients-debug
```

**Tools**:
- `wayland-info` - Show globals, formats, capabilities
- `wayland-debug` - Protocol traffic debugger

**Location**: `test-clients/debug/bin/`

**Usage**:
```bash
export WAYLAND_DISPLAY=wayland-0
./test-clients/debug/bin/wayland-info
./test-clients/debug/bin/wayland-debug weston-simple-shm
```

### 4. Nested Compositors

**Purpose**: Test compositor robustness with nested compositors

**Status**: Requires full Weston build with nested backend support

**Clients**:
- `weston --backend=wayland` - Weston nested
- `cage` - Single-client maximizing compositor (requires porting)

**Usage**:
```bash
export WAYLAND_DISPLAY=wayland-0
weston --backend=wayland
```

## Building Individual Clients

### Build Specific Category

```bash
# Minimal clients only
make test-clients-minimal

# Weston clients only
make test-clients-weston

# Debug tools only
make test-clients-debug
```

### Manual Build

```bash
# Minimal clients
cd scripts/test-clients
./build-minimal.sh

# Debug tools
./build-debug-tools.sh

# Weston clients
./build-weston.sh
```

## Running Tests

### Run All Tests

```bash
make test-clients-run
```

This will:
1. Check if compositor is running
2. Run all available test clients
3. Report pass/fail/skip status

### Run Individual Client

```bash
export WAYLAND_DISPLAY=wayland-0
./test-clients/bin/weston-simple-shm
```

### Interactive Testing

Some clients are interactive and require user input:

```bash
export WAYLAND_DISPLAY=wayland-0
./test-clients/bin/weston-eventdemo  # Shows pointer/keyboard events
./test-clients/bin/weston-keyboard   # Keyboard input test
./test-clients/bin/weston-dnd         # Drag and drop test
```

## Test Client Descriptions

### Rendering Tests

**weston-simple-shm**
- Tests shared memory buffers
- Creates a colored rectangle
- Verifies basic surface rendering

**weston-simple-egl**
- Tests EGL/OpenGL ES rendering
- Requires EGL support
- Verifies GPU-accelerated rendering

**weston-transformed**
- Tests surface transformations (rotation, scaling)
- Verifies transform matrix handling

**weston-subsurfaces**
- Tests sub-surface hierarchy
- Verifies parent-child relationships
- Tests sub-surface positioning

**weston-simple-damage**
- Tests incremental damage regions
- Verifies efficient repainting
- Tests damage accumulation

### Input Tests

**weston-simple-touch**
- Tests touch input events
- Multi-touch support
- Touch point tracking

**weston-eventdemo**
- Shows all pointer/keyboard events
- Useful for debugging input handling
- Real-time event inspection

**weston-keyboard**
- Keyboard input test
- Key repeat testing
- Modifier key handling

### Drag and Drop / Clipboard

**weston-dnd**
- Drag and drop protocol test
- Source and destination testing
- MIME type handling

**weston-cliptest**
- Clipboard protocol test
- Copy/paste operations
- Multiple clipboard selections

### Other Clients

**weston-image**
- Displays PNG images
- Image format support
- Surface content testing

**weston-editor**
- Text input protocol test
- IME (Input Method Editor) support
- Text composition testing

## macOS-Specific Notes

### EGL Support

EGL clients require EGL support on macOS. Options:
- MoltenVK (Vulkan-to-Metal)
- Angle (OpenGL ES-to-Metal)
- Software fallback (slower)

### Shared Memory

macOS uses POSIX shared memory (`shm_open`). The build scripts handle this automatically.

### Nested Compositors

Running nested compositors requires:
- Full Wayland protocol support
- Proper buffer handling
- Input event forwarding

### XWayland

XWayland support is not included in the test clients. See XWayland documentation for testing X11 clients.

## Troubleshooting

### "Failed to connect to Wayland display"

**Problem**: Client can't connect to compositor

**Solution**:
```bash
# Check if compositor is running
ls -la ${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}/wayland-*

# Set WAYLAND_DISPLAY
export WAYLAND_DISPLAY=wayland-0

# Check XDG_RUNTIME_DIR
export XDG_RUNTIME_DIR=/tmp/wayland-runtime
```

### "Compositor or SHM not available"

**Problem**: Required globals not advertised

**Solution**: Check compositor implementation:
- `wl_compositor` global must be advertised
- `wl_shm` global must be advertised
- Protocol version must match

### EGL Clients Fail

**Problem**: EGL clients don't run

**Solution**:
- Install EGL support (MoltenVK or Angle)
- Or skip EGL clients (use SHM-only clients)

### Build Failures

**Problem**: Build scripts fail

**Solution**:
```bash
# Check dependencies
pkg-config --exists wayland-client wayland-server pixman-1

# Install missing dependencies
brew install meson ninja pixman

# Build Wayland if needed
make wayland
```

## Integration with CI/CD

### Automated Testing

```bash
#!/bin/bash
# CI test script

# Build compositor
make compositor

# Start compositor in background
make run-compositor &
COMPOSITOR_PID=$!

# Wait for compositor to start
sleep 2

# Build test clients
make test-clients-build

# Run tests
make test-clients-run
TEST_RESULT=$?

# Cleanup
kill $COMPOSITOR_PID

exit $TEST_RESULT
```

## Next Steps

1. **Build test clients**: `make test-clients-build`
2. **Start compositor**: `make run-compositor`
3. **Run tests**: `make test-clients-run`
4. **Debug failures**: Check logs in `/tmp/wawona-test-*.log`
5. **Extend tests**: Add custom test clients as needed

## References

- [Wayland Protocol](https://wayland.freedesktop.org/docs/html/)
- [Weston Documentation](https://gitlab.freedesktop.org/wayland/weston)
- [Wayland Book](https://wayland-book.com/)

