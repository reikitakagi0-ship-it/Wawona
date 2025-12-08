# Dependencies

Minimal dependency tracking system for Wawona with support for building for iOS, macOS, and Android. Supports both GitHub and GitLab repositories with platform-specific patches.

## Usage

### Adding Dependencies

Edit `registry.nix` to add dependencies:

```nix
{
  wayland = {
    # Source: "github" (default) or "gitlab"
    source = "gitlab";
    
    owner = "wayland";
    repo = "wayland";
    rev = "abc123...";  # or tag = "v1.0.0", or branch = "main"
    
    # Specify which platforms to build for
    platforms = [ "ios" "macos" "android" ];
    
    # Specify build system (cmake, meson, autotools, cargo/rust)
    buildSystem = "meson";
    
    # Platform-specific build flags
    buildFlags = {
      ios = [ "-Dlibraries=false" ];
      macos = [ "-Dlibraries=false" ];
      android = [ "-Dlibraries=false" ];
    };
    
    # Platform-specific patches (paths relative to ./patches/)
    patches = {
      ios = [ ./patches/wayland/ios-remove-linux-syscalls.patch ];
      macos = [ ./patches/wayland/macos-epoll-shim.patch ];
      android = [ ./patches/wayland/android-remove-linux-syscalls.patch ];
    };
  };
}
```

### Patching Dependencies

Patches are applied using Nix's built-in patching mechanisms:

1. **Patch Files**: Place patch files in `patches/<dependency>/` and reference them in `registry.nix`
2. **Inline Patching**: Use `postPatch` in `build.nix` for simple substitutions
3. **Upstream Patches**: Use `fetchpatch` to fetch patches from GitHub/GitLab PRs

See `patches/README.md` for detailed patching documentation.

### Using in flake.nix

Import the module and use the inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    
    # Import dependencies module
    deps = {
      url = "path:./dependencies";
      flake = false;
    };
  };
  
  outputs = { self, nixpkgs, deps }: let
    pkgs = import nixpkgs { system = "aarch64-darwin"; };
    
    dependencies = import ./dependencies/default.nix {
      lib = pkgs.lib;
      inherit pkgs;
    };
    
    # Get dependencies for a specific platform
    iosDeps = dependencies.forPlatform "ios";
    macosDeps = dependencies.forPlatform "macos";
    androidDeps = dependencies.forPlatform "android";
    
    # Use dependencies.inputs to add to your inputs
    # Or use dependencies.getInput "name" to get a specific one
  in {
    # Build packages for each platform
    packages.aarch64-darwin = {
      ios-dependencies = import ./dependencies/build.nix {
        inherit (pkgs) lib;
        inherit pkgs stdenv buildPackages;
      };
    };
  };
}
```

### Building Dependencies

The `build.nix` module provides functions to build dependencies for each platform:

```nix
let
  buildModule = import ./dependencies/build.nix {
    inherit (pkgs) lib;
    inherit pkgs stdenv buildPackages;
  };
in
{
  # Build all iOS dependencies
  ios-deps = buildModule.ios;
  
  # Build all macOS dependencies
  macos-deps = buildModule.macos;
  
  # Build all Android dependencies
  android-deps = buildModule.android;
  
  # Or build specific dependency for a platform
  wayland-ios = buildModule.buildForIOS "wayland" (dependencies.get "wayland");
}
```

## Structure

- `registry.nix` - Registry of dependencies (GitHub/GitLab) with platform and build configuration
- `default.nix` - Nix module that converts registry to flake input format and provides query functions
- `build.nix` - Build module for cross-compiling dependencies for iOS, macOS, and Android
- `patches/` - Platform-specific patches for dependencies (see `patches/README.md`)
- `README.md` - This file

## Platform Support

All dependencies can specify which platforms they should be built for:
- `ios` - iOS (arm64, iOS 15.0+)
- `macos` - macOS (native architecture)
- `android` - Android (aarch64, via Android NDK)

If `platforms` is not specified, the dependency will be built for all platforms by default.

## Build Systems Supported

- **cmake** - CMake-based builds
- **meson** - Meson build system
- **autotools** - Autotools (autoconf/automake/libtool)
- **cargo/rust** - Rust/Cargo builds

## Current Dependencies

The following dependencies are currently configured in `registry.nix`:

- **wayland** - Core Wayland protocol library (GitLab)
- **waypipe** - Network transparency for Wayland applications, Rust implementation (GitLab)
- **mesa-kosmickrisp** - Vulkan-to-Metal driver built from Mesa source (GitLab)

Each dependency includes platform-specific patches for iOS, macOS, and Android compatibility.

### Key Features

- **Mesa-KosmicKrisp**: Built from Mesa source code, compiles as .dylib for macOS/iOS
- **Waypipe-rs**: Rust implementation with Vulkan support via KosmicKrisp dependency
- **Cross-compilation**: Full support for iOS, macOS, and Android builds via Nix
