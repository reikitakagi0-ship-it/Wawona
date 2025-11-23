# Wayland Test Clients - Quick Start Guide

Quick guide to building and testing Wayland clients on macOS.

## 🚀 Quick Start

### 1. Build All Test Clients

```bash
make test-clients-build
```

This builds:
- ✅ Minimal test clients (`simple-shm`, `simple-damage`)
- ✅ Debugging tools (`wayland-info`, `wayland-debug`)
- ✅ Weston demo clients (12+ clients)
- ✅ Nested compositor scripts

### 2. Start Compositor

```bash
# Terminal 1
make run-compositor
```

### 3. Run Tests

```bash
# Terminal 2
make test-clients-run
```

## 📋 Available Test Clients

### Minimal Clients (Fast Build)

```bash
make test-clients-minimal
```

**Clients**:
- `simple-shm` - Basic SHM buffer test
- `simple-damage` - Damage region testing

### Weston Demo Clients (Comprehensive)

```bash
make test-clients-weston
```

**Rendering Tests**:
- `weston-simple-shm` - SHM buffer test
- `weston-simple-egl` - EGL/OpenGL ES test
- `weston-transformed` - Surface transformations
- `weston-subsurfaces` - Sub-surface hierarchy
- `weston-simple-damage` - Incremental damage

**Input Tests**:
- `weston-simple-touch` - Touch input
- `weston-eventdemo` - Event inspection
- `weston-keyboard` - Keyboard test

**Drag & Drop / Clipboard**:
- `weston-dnd` - Drag and drop
- `weston-cliptest` - Clipboard test

**Other**:
- `weston-image` - PNG display
- `weston-editor` - Text input protocol

### Debugging Tools

```bash
make test-clients-debug
```

**Tools**:
- `wayland-info` - Show globals and capabilities
- `wayland-debug` - Protocol traffic debugger

### Nested Compositors

```bash
make test-clients-nested
```

**Scripts**:
- `weston-nested` - Run Weston nested inside Wawona

## 🧪 Running Individual Clients

```bash
# Set Wayland display
export WAYLAND_DISPLAY=wayland-0

# Run a client
./test-clients/bin/weston-simple-shm
./test-clients/bin/wayland-info
./test-clients/bin/simple-shm
```

## 📍 Client Locations

All clients are installed to:
- `test-clients/bin/` - Main directory (symlinks)
- `test-clients/minimal/bin/` - Minimal clients
- `test-clients/weston/bin/` - Weston clients
- `test-clients/debug/bin/` - Debug tools
- `test-clients/nested/bin/` - Nested compositor scripts

## 🔍 Testing Protocol Compliance

### Basic Protocol Test

```bash
# 1. Start compositor
make run-compositor

# 2. Check globals
./test-clients/bin/wayland-info

# 3. Test SHM buffers
./test-clients/bin/simple-shm

# 4. Test damage regions
./test-clients/bin/simple-damage
```

### Comprehensive Test Suite

```bash
# Run all automated tests
make test-clients-run
```

### Interactive Tests

```bash
# Event inspection (shows all events)
./test-clients/bin/weston-eventdemo

# Keyboard test
./test-clients/bin/weston-keyboard

# Drag and drop test
./test-clients/bin/weston-dnd
```

## 🐛 Troubleshooting

### "Failed to connect to Wayland display"

**Solution**:
```bash
# Check compositor is running
ls -la ${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}/wayland-*

# Set environment
export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/tmp/wayland-runtime
```

### "Compositor or SHM not available"

**Solution**: Check compositor advertises required globals:
- `wl_compositor`
- `wl_shm`

### Build Failures

**Solution**:
```bash
# Check dependencies
pkg-config --exists wayland-client wayland-server pixman-1

# Install missing
brew install meson ninja pixman

# Build Wayland if needed
make wayland
```

## 📚 More Information

- **Full Documentation**: `docs/TEST_CLIENTS.md`
- **Test Client README**: `scripts/test-clients/README.md`
- **Makefile Help**: `make help`

## 🎯 Next Steps

1. ✅ Build test clients: `make test-clients-build`
2. ✅ Start compositor: `make run-compositor`
3. ✅ Run tests: `make test-clients-run`
4. ✅ Debug failures: Check logs in `/tmp/wawona-test-*.log`
5. ✅ Extend tests: Add custom clients as needed

## 💡 Tips

- **Fast testing**: Use minimal clients (`simple-shm`, `simple-damage`)
- **Comprehensive testing**: Use Weston clients
- **Debugging**: Use `wayland-info` and `wayland-debug`
- **Protocol inspection**: Run `wayland-info` to see all globals
- **Interactive testing**: Use `weston-eventdemo` to see events in real-time

