# Compilation Guide

This guide explains how to compile the Wawona project and its dependencies using Nix.

## Build Commands

We use **Nix Flakes** to manage builds. The general syntax for building a target is:

```bash
nix build .#<target-name> [flags]
```

### Common Flags

- **`-L` (or `--print-build-logs`)**:
  - **What it does**: Prints the full build logs to the terminal as the build proceeds.
  - **When to use**: Use this when a build is failing or taking a long time, and you want to see what is happening (e.g., compiler output, errors).
  - **Example**: `nix build .#waypipe-ios -L`

- **`--show-trace`**:
  - **What it does**: Prints a stack trace if the Nix expression evaluation fails.
  - **When to use**: Use this if you get a generic "error: ..." message from Nix to pinpoint where in the `.nix` files the error occurred.

## Available Targets

The following targets are available for compilation. They are categorized by platform.

### 📱 iOS Targets
These targets compile for `aarch64-apple-ios` using the iOS SDK.

- **`waypipe-ios`**: Compiles Waypipe for iOS (includes bindings for ffmpeg, lz4, zstd).
- **`ffmpeg-ios`**: FFmpeg libraries (avcodec, avutil, etc.) for iOS.
- **`libwayland-ios`**: Wayland client and server libraries for iOS.
- **`kosmickrisp-ios`**: Vulkan-based Wayland compositor support.
- **`lz4-ios`**: LZ4 compression library.
- **`zstd-ios`**: Zstandard compression library.
- **`expat-ios`**: XML parsing library.
- **`libffi-ios`**: Foreign Function Interface library.
- **`libxml2-ios`**: XML C parser and toolkit.
- **`epoll-shim-ios`**: Epoll emulation for BSD systems.

### 💻 macOS Targets
These targets compile for `aarch64-apple-darwin` (macOS).

- **`waypipe-macos`**
- **`ffmpeg-macos`**
- **`libwayland-macos`**
- **`kosmickrisp-macos`**
- **`lz4-macos`**
- **`zstd-macos`**
- **`expat-macos`**
- **`libffi-macos`**
- **`libxml2-macos`**
- **`epoll-shim-macos`**

### 🤖 Android Targets
These targets compile for Android (aarch64).

- **`waypipe-android`**
- **`ffmpeg-android`**
- **`libwayland-android`**
- **`swiftshader-android`**: CPU-based Vulkan implementation.
- **`lz4-android`**
- **`zstd-android`**
- **`expat-android`**
- **`libffi-android`**
- **`libxml2-android`**

## Examples

**Build Waypipe for iOS with logs:**
```bash
nix build .#waypipe-ios -L
```

**Build FFmpeg for Android:**
```bash
nix build .#ffmpeg-android
```

**Run Waypipe on macOS:**
You can run waypipe directly on macOS using `nix run`:
```bash
nix run .#waypipe-macos -- --help
nix run .#waypipe-macos -- --version
nix run .#waypipe-macos -- ssh user@host command
```

**Check the build result:**
By default, `nix build` creates a `result` symlink in the current directory containing the build output (e.g., `result/bin/waypipe`).

```bash
ls -l result/bin/
file result/bin/waypipe
```

# updating dependencies

Most of the dependencies we handle with nix. Such as libffi, libwayland, epoll-shim etc. 

But for our Android build, `nix run .#update-android-deps` is available to update all gradle dependencies. I don't really know if this is the best way to do such a thing. but its there...