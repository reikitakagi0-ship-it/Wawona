# Wawona Compositor Usage Guide

## Overview

Wawona is a **from-scratch Wayland compositor** for macOS that:
- Uses `libwayland-server` (no WLRoots - Linux-only)
- Renders Wayland surfaces using **CALayer**
- Runs in a native **NSWindow**
- Supports mouse and keyboard input via **NSEvent**

## Building

### Prerequisites

1. **Install dependencies**:
   ```bash
   ./check-deps.sh
   ```

2. **Install Wayland** (if not already installed):
   ```bash
   ./install-wayland.sh
   ```

### Build

```bash
./build.sh
```

Options:
- `./build.sh --clean` - Clean build directory first
- `./build.sh --run` - Build and run immediately
- `./build.sh --install` - Install to `/usr/local/bin`

## Running

### Start the Compositor

```bash
./build.sh --run
# Or directly:
./build/Wawona
```

The compositor will:
1. Create `XDG_RUNTIME_DIR` if not set (in `/tmp/wayland-runtime`)
2. Create a Wayland socket (e.g., `/tmp/wayland-runtime/wayland-0`)
3. Open an NSWindow titled "Wawona"
4. Print connection instructions

### Connect Clients

In a **separate terminal**:

```bash
# Set Wayland display
export WAYLAND_DISPLAY=wayland-0  # (or whatever socket name was printed)

# Run a Wayland client
./test_client  # (if you built the test client)
```

## Architecture

```
┌─────────────────────────────────────┐
│      NSWindow (macOS)               │
│  ┌───────────────────────────────┐ │
│  │   CALayer (Root Layer)        │ │
│  │  ┌──────┐  ┌──────┐          │ │
│  │  │Surf 1│  │Surf 2│  ...     │ │
│  │  └──────┘  └──────┘          │ │
│  └───────────────────────────────┘ │
└─────────────────────────────────────┘
           ▲
           │
    SurfaceRenderer
           ▲
           │
┌─────────────────────────────────────┐
│  Wayland Protocol Handlers           │
│  • wl_compositor                    │
│  • wl_surface                       │
│  • wl_output                        │
│  • wl_seat (input)                  │
│  • wl_shm (buffers)                 │
│  • xdg_wm_base (window mgmt)       │
└─────────────────────────────────────┘
           ▲
           │
┌─────────────────────────────────────┐
│      libwayland-server              │
└─────────────────────────────────────┘
```

## Features

### ✅ Implemented

- **Core Protocols**:
  - `wl_compositor` - Surface creation
  - `wl_surface` - Surface management
  - `wl_output` - Output geometry
  - `wl_seat` - Input devices
  - `wl_shm` - Shared memory buffers

- **Shell Protocol**:
  - `xdg_wm_base` - Window manager base
  - `xdg_surface` - Surface roles
  - `xdg_toplevel` - Top-level windows

- **Rendering**:
  - SHM buffer → CGImage conversion
  - CALayer rendering pipeline
  - Multiple surface support
  - 60 FPS frame rendering

- **Input**:
  - Mouse events (motion, buttons)
  - Keyboard events (key press/release)
  - NSEvent → Wayland conversion

### 🚧 Partial/TODO

- Window management (move, resize, minimize)
- Popup surfaces
- Touch input
- Clipboard/data transfer
- Performance optimization

## Protocol Support

| Protocol | Status | Notes |
|----------|--------|-------|
| `wl_compositor` | ✅ Complete | Surface creation |
| `wl_surface` | ✅ Complete | Buffer attachment, commit |
| `wl_output` | ✅ Complete | Geometry, modes |
| `wl_seat` | ✅ Complete | Pointer, keyboard |
| `wl_shm` | ✅ Complete | Shared memory buffers |
| `xdg_wm_base` | ✅ Basic | Window management base |
| `xdg_surface` | ✅ Basic | Surface roles |
| `xdg_toplevel` | ✅ Basic | Top-level windows |
| `xdg_popup` | ⏳ TODO | Popup surfaces |

## File Structure

```
Wawona/
├── src/
│   ├── main.m                    # Entry point
│   ├── macos_backend.{h,m}       # Main compositor backend
│   ├── wayland_compositor.{h,c}  # wl_compositor implementation
│   ├── wayland_output.{h,c}       # wl_output implementation
│   ├── wayland_seat.{h,c}        # wl_seat implementation
│   ├── wayland_shm.{h,c}         # wl_shm implementation
│   ├── xdg_shell.{h,c}           # xdg-shell implementation
│   ├── surface_renderer.{h,m}    # CALayer rendering
│   └── input_handler.{h,m}       # Input event conversion
├── protocols/
│   └── xdg-shell/
│       └── xdg-shell.xml         # Protocol definition
├── build.sh                       # Build script
├── install-wayland.sh             # Wayland installation
└── check-deps.sh                  # Dependency checker
```

## Environment Variables

- `WAYLAND_DISPLAY` - Socket name (e.g., `wayland-0`)
- `XDG_RUNTIME_DIR` - Runtime directory (auto-created if not set)

## Troubleshooting

### Compositor won't start
- Check dependencies: `./check-deps.sh`
- Verify Wayland is installed: `pkg-config --exists wayland-server`
- Check logs for specific errors

### Clients can't connect
- Verify `WAYLAND_DISPLAY` matches socket name
- Check `XDG_RUNTIME_DIR` is set and writable
- Ensure compositor is running

### Surfaces don't render
- Check compositor logs
- Verify SHM buffer format is supported
- Check CALayer is set up correctly

### Input doesn't work
- Ensure compositor window has focus
- Check input handling was initialized
- Verify NSEvent monitoring is active

## Development

### Adding New Protocols

1. Get protocol XML (from wayland-protocols)
2. Generate bindings: `wayland-scanner server-header protocol.xml protocol.h`
3. Implement handlers in new `protocol.{h,c}` files
4. Register global in `macos_backend.m`

### Debugging

- Enable verbose logging in `main.m`
- Check Wayland protocol errors
- Monitor NSRunLoop events
- Use Instruments for performance profiling

## References

- [Wayland Book](https://wayland-book.com/)
- [Wayland Protocol Spec](https://wayland.freedesktop.org/docs/html/)
- [macOS Core Animation Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/)

