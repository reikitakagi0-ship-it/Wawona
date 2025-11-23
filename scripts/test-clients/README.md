# Wayland Test Clients for macOS

This directory contains build scripts and ported test clients for comprehensive Wayland compositor testing on macOS.

## Overview

These test clients are essential for compositor developers to verify:
- Buffer types (SHM, DMA-BUF, EGL)
- Protocol compliance (xdg-shell, input, output, etc.)
- Surface management (subsurfaces, transformations)
- Input handling (keyboard, mouse, touch)
- Drag-and-drop and clipboard
- Nested compositor support

## Categories

### 1. Weston Demo Clients
- `weston-simple-shm` - SHM buffer test
- `weston-simple-egl` - EGL/OpenGL ES test
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

### 2. Minimal Test Clients
- `simple-shm` - Minimal SHM client
- `simple-egl` - Minimal EGL client
- `simple-damage` - Minimal damage test
- `simple-subsurface` - Minimal subsurface test

### 3. Wayland Debugging Tools
- `wayland-info` - Show globals, formats, capabilities
- `wayland-debug` - Protocol traffic debugger

### 4. Nested Compositors
- `weston-nested` - Weston running nested
- `cage` - Single-client maximizing compositor

## Building

### Build All Test Clients

```bash
make test-clients-all
```

### Build Individual Categories

```bash
# Weston clients
make test-clients-weston

# Minimal clients
make test-clients-minimal

# Debugging tools
make test-clients-debug

# Nested compositors
make test-clients-nested
```

### Build Individual Clients

```bash
# Example: Build weston-simple-shm
make test-clients-weston-simple-shm
```

## Running Tests

### Run All Tests

```bash
make test-clients-run
```

### Run Individual Tests

```bash
# Set Wayland display (if compositor is running)
export WAYLAND_DISPLAY=wayland-0

# Run a test client
./test-clients/weston/weston-simple-shm
```

## Requirements

- Wayland libraries (libwayland-client, libwayland-server)
- EGL libraries (for EGL clients)
- Pixman (for SHM clients)
- Meson and Ninja (for building Weston)
- CMake (for some clients)

## macOS-Specific Notes

- EGL support requires MoltenVK or similar (for OpenGL ES on Metal)
- Some clients may need porting from Linux-specific code
- Nested compositors require full Wayland protocol support

