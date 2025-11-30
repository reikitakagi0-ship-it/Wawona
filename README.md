# Wawona

[![Build Status](https://github.com/YOUR_USERNAME/Wawona/actions/workflows/build.yml/badge.svg)](https://github.com/YOUR_USERNAME/Wawona/actions/workflows/build.yml)
[![Code Style](https://img.shields.io/badge/code%20style-clang--format-blue)](https://clang.llvm.org/docs/ClangFormat.html)

<div align="center">
  <img src="preview1.png" alt="Wawona - Wayland Compositor for macOS Preview" width="800"/>
</div>

**Wawona** is a native Wayland Compositor for macOS and iOS. It is built from scratch using `libwayland-server` for protocol handling and **Metal** for high-performance rendering. It features a full Cocoa/UIKit compatibility layer for seamless integration with Apple's operating systems.

## Key Features

- **Native macOS & iOS Support**: Runs natively on both platforms without Linux VMs or containers.
- **Metal Rendering**: Uses Metal for hardware-accelerated rendering of Wayland surfaces.
- **Static Frameworks**: 
    - **Wayland**: Compiled as a static framework.
    - **KosmicKrisp**: Vulkan driver compiled as a static framework (enables DMA-BUF).
    - **Waypipe**: Compiled as a static framework for network transparency.
- **App Launcher**: Built-in native Wayland client that acts as an app launcher on startup.
- **No WLRoots**: Custom compositor implementation tailored for Apple platforms.

## Architecture

Wawona is designed as a native macOS/iOS application that hosts a Wayland compositor:

1.  **Entry Point**: `src/main.m` initializes the native application (`NSApplication` or `UIApplication`).
2.  **Compositor Core**: `src/WawonaCompositor.m` manages the Wayland display, event loop, and window management.
3.  **Rendering**: `src/metal_renderer.m` and `src/surface_renderer.m` handle drawing Wayland buffers to the screen using Metal or CoreGraphics.
4.  **Input**: `src/input_handler.m` translates macOS/iOS input events into Wayland events.

## Prerequisites

- **macOS**: Xcode with command-line tools.
- **iOS**: Xcode with iOS Simulator SDK.
- **Build Tools**: `cmake`, `meson`, `ninja`, `pkg-config`.

## Building

### macOS

To build Wawona for macOS:

```bash
# Build all dependencies (Wayland, KosmicKrisp, Waypipe, etc.)
make deps-macos

# Build and run the compositor
make compositor
```

### iOS Simulator

To build Wawona for iOS Simulator:

```bash
# Build all dependencies and the compositor
make ios-compositor
```

This will:
1. Cross-compile all dependencies for the iOS Simulator.
2. Build the Wawona iOS app bundle.
3. Launch the app in the iOS Simulator.

## Project Structure

- **`src/`**: Unified source code for both macOS and iOS.
- **`dependencies/`**: Source code for third-party dependencies (Wayland, etc.).
- **`scripts/`**: Build and utility scripts.
- **`build/`**: Build artifacts (generated).
- **`compat/`**: Compatibility headers and stubs.

## License

[MIT License](LICENSE)
