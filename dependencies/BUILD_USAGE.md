# Building Dependencies

This document explains how to build individual dependencies for each platform using Nix.

## Building Dependencies

Each dependency can be built for iOS, macOS, or Android using the following format:

```bash
nix build .#<dependency-name>-<platform>
```

### Examples

Build Wayland for iOS:
```bash
nix build .#wayland-ios
```

Build Mesa-KosmicKrisp for macOS:
```bash
nix build .#mesa-kosmickrisp-macos
```

Build Waypipe for Android:
```bash
nix build .#waypipe-android
```

## Available Dependencies

Based on `dependencies/registry.nix`, the following dependencies are available:

### Wayland
- `wayland-ios` - Wayland for iOS
- `wayland-macos` - Wayland for macOS
- `wayland-android` - Wayland for Android

### Waypipe
- `waypipe-ios` - Waypipe (Rust) for iOS
- `waypipe-macos` - Waypipe (Rust) for macOS
- `waypipe-android` - Waypipe (Rust) for Android

### Mesa-KosmicKrisp
- `mesa-kosmickrisp-ios` - Mesa with KosmicKrisp Vulkan driver for iOS
- `mesa-kosmickrisp-macos` - Mesa with KosmicKrisp Vulkan driver for macOS

## Building All Dependencies for a Platform

To build all dependencies for a specific platform, you can use:

```bash
# Build all iOS dependencies
nix build .#wayland-ios .#waypipe-ios .#mesa-kosmickrisp-ios

# Build all macOS dependencies
nix build .#wayland-macos .#waypipe-macos .#mesa-kosmickrisp-macos

# Build all Android dependencies
nix build .#wayland-android .#waypipe-android
```

## Output Location

After building, the output will be in `result/`:

```bash
nix build .#wayland-macos
ls -la result/
```

The built artifacts (libraries, headers, etc.) will be in the `result/` directory.

## Development

To enter a development shell with all build tools:

```bash
nix develop
```

This provides access to cmake, meson, ninja, pkg-config, and other build tools needed to build dependencies.
