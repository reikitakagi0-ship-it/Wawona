# Dependency Management System

## Overview

The dependency management system in `./dependencies` provides a scalable, maintainable way to build dependencies for iOS, macOS, and Android using Nix cross-compilation. Each dependency is self-contained, and platform builders are generic and reusable.

## Structure

```
dependencies/
├── deps/                    # Individual dependency definitions
│   ├── wayland.nix
│   ├── waypipe.nix
│   └── mesa-kosmickrisp.nix
├── platforms/                # Platform-specific build logic
│   ├── ios.nix
│   ├── macos.nix
│   └── android.nix
├── common/                   # Shared utilities
│   ├── common.nix           # Helper functions
│   └── registry.nix         # Aggregates all dependencies
├── utils/                    # Platform-specific utilities
│   ├── xcode-wrapper.nix   # Xcode detection for iOS
│   └── find-xcode.sh
├── build.nix                 # Main orchestrator
└── patches/                  # Platform-specific patches
    ├── wayland/
    ├── waypipe/
    └── kosmickrisp-vulkan/
```

## Adding a New Dependency

### Step 1: Create Dependency File

Create `dependencies/deps/newdep.nix`:

```nix
{
  source = "github";  # or "gitlab"
  owner = "owner";
  repo = "repo";
  tag = "v1.0.0";     # or rev = "abc123..." or branch = "main"
  sha256 = "sha256-...";
  platforms = [ "ios" "macos" "android" ];
  buildSystem = "meson";  # or "cmake", "cargo", "autotools"
  buildFlags = {
    ios = [ "-Dflag1" "-Dflag2" ];
    macos = [ "-Dflag1" ];
    android = [ "-Dflag1" ];
  };
  patches = {
    ios = [ ../patches/newdep/ios-fix.patch ];
    macos = [];
    android = [];
  };
  dependencies = {
    macos = [ "expat" "libffi" ];
    ios = [ "expat" "libffi" ];
    android = [ "expat" ];
  };
}
```

### Step 2: Register Dependency

Add to `dependencies/common/registry.nix`:

```nix
{
  wayland = import ../deps/wayland.nix;
  waypipe = import ../deps/waypipe.nix;
  "mesa-kosmickrisp" = import ../deps/mesa-kosmickrisp.nix;
  newdep = import ../deps/newdep.nix;
}
```

### Step 3: Build

```bash
nix build --show-trace '.#newdep-macos'
nix build --show-trace '.#newdep-ios'
nix build --show-trace '.#newdep-android'
```

## Dependency Configuration

### Source Options

- `source`: `"github"` or `"gitlab"` (default: `"github"`)
- `owner`: Repository owner
- `repo`: Repository name
- `tag`: Git tag (e.g., `"v1.0.0"`)
- `rev`: Git commit hash (e.g., `"abc123..."`)
- `branch`: Git branch (e.g., `"main"`)
- `sha256`: Source hash (required)

### Build Configuration

- `platforms`: List of platforms: `[ "ios" "macos" "android" ]`
- `buildSystem`: `"meson"`, `"cmake"`, `"cargo"`, `"rust"`, or `"autotools"`
- `buildFlags`: Platform-specific flags
  ```nix
  buildFlags = {
    ios = [ "-Dflag1" "-Dflag2" ];
    macos = [ "-Dflag1" ];
  };
  ```
- `patches`: Platform-specific patches
  ```nix
  patches = {
    ios = [ ../patches/dep/ios-fix.patch ];
    macos = [];
  };
  ```

### Rust/Cargo Specific

- `cargoHash`: Cargo hash (SRI format)
- `cargoSha256`: Legacy cargo hash
- `cargoLock`: Path to Cargo.lock (optional)

### Dependencies

Declare platform-specific dependencies:

```nix
dependencies = {
  macos = [ "expat" "libffi" "libxml2" ];
  ios = [ "expat" "libffi" "libxml2" ];
  android = [ "expat" "libffi" ];
};
```

Supported dependency names:
- `expat`, `libffi`, `libxml2`
- `libclc`, `zlib`, `zstd`, `llvm`

## Platform Builders

Platform builders in `platforms/` are generic and handle all build systems:

- `platforms/ios.nix` - iOS cross-compilation with Xcode integration
- `platforms/macos.nix` - Native macOS builds
- `platforms/android.nix` - Android cross-compilation

Each platform builder:
1. Fetches source using `common.fetchSource`
2. Applies platform-specific patches
3. Resolves dependencies from `entry.dependencies`
4. Builds using the specified build system

## Build Systems

### Meson

```nix
buildSystem = "meson";
buildFlags = {
  macos = [ "-Doption=value" ];
};
```

### CMake

```nix
buildSystem = "cmake";
buildFlags = {
  macos = [ "-DOPTION=value" ];
};
```

### Cargo/Rust

```nix
buildSystem = "cargo";
cargoHash = "sha256-...";
buildFlags = {
  macos = [ "--target=aarch64-apple-darwin" "--features=feature" ];
};
```

### Autotools

```nix
buildSystem = "autotools";
buildFlags = {
  macos = [ "--enable-feature" ];
};
```

## iOS Specifics

### Xcode Integration

iOS builds automatically detect and use Xcode:
- Finds Xcode via `utils/find-xcode.sh`
- Sets `DEVELOPER_DIR`, `SDKROOT`, `PATH`
- Uses Xcode's compiler for iOS builds

### Cross-Compilation

Uses `pkgs.pkgsCross.iphone64` for iOS builds. Dependencies are resolved from `iosPkgs` (e.g., `iosPkgs.expat`).

## Building Dependencies

### Build Single Dependency

```bash
nix build --show-trace '.#wayland-macos'
nix build --show-trace '.#wayland-ios'
nix build --show-trace '.#wayland-android'
```

### Build All Dependencies for Platform

```bash
nix build --show-trace '.#ios'      # All iOS dependencies
nix build --show-trace '.#macos'    # All macOS dependencies
nix build --show-trace '.#android'  # All Android dependencies
```

### Build from Flake

All dependencies are available as flake outputs:

```bash
nix build --show-trace '.#wayland-macos'
nix build --show-trace '.#waypipe-ios'
nix build --show-trace '.#mesa-kosmickrisp-macos'
```

## Scalability

The structure scales to 100+ dependencies:

1. **One file per dependency** - Easy to add/modify without touching other files
2. **Dependencies declared in dependency files** - Self-contained configuration
3. **Platform files are generic** - No hardcoded dependency logic
4. **Registry is simple aggregation** - Just imports all dependencies
5. **Easy to add new platforms** - Create new platform file following the pattern

## Troubleshooting

### Build Fails with "dependency not found"

Ensure the dependency is listed in `entry.dependencies.<platform>` and the dependency name is supported in the platform builder's `getDeps` function.

### iOS Build Fails

- Ensure Xcode is installed
- Check that `utils/find-xcode.sh` can find Xcode
- Verify iOS SDK is available

### Hash Mismatch

Update `sha256` in the dependency file. Nix will show the correct hash on first build.

## Examples

See existing dependencies for examples:
- `deps/wayland.nix` - Meson build with dependencies
- `deps/waypipe.nix` - Cargo/Rust build
- `deps/mesa-kosmickrisp.nix` - Complex Meson build with many flags
