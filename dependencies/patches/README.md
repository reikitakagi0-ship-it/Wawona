# Dependency Patches

This directory contains platform-specific patches for dependencies. Patches are applied during the Nix build process using Nix's built-in patching mechanisms.

## Directory Structure

```
patches/
├── wayland/
│   ├── ios-remove-linux-syscalls.patch
│   ├── macos-epoll-shim.patch
│   └── android-remove-linux-syscalls.patch
├── waypipe/
│   ├── ios-disable-linux-gpu.patch
│   ├── macos-disable-linux-gpu.patch
│   └── android-gralloc-support.patch
└── kosmickrisp-vulkan/
    ├── ios-metal-integration.patch
    └── macos-metal-integration.patch
```

## Nix Patching Mechanisms

Patches are applied using the following Nix mechanisms (in order of preference):

### 1. Patch Files (`patches = [ ./patches/... ]`)

Patch files are automatically applied before `configurePhase`. This is the standard way to apply patches:

```nix
patches = [
  ./patches/wayland/ios-remove-linux-syscalls.patch
];
```

### 2. Inline Patching (`postPatch`)

For small changes, use `substituteInPlace` in `postPatch`:

```nix
postPatch = ''
  substituteInPlace src/config.h \
    --replace "#define DEBUG 0" "#define DEBUG 1"
'';
```

### 3. Fetching Patches from Upstream (`fetchpatch`)

If patches are available upstream (e.g., GitHub PRs):

```nix
patches = [
  (fetchpatch {
    url = "https://github.com/foo/bar/pull/123.patch";
    sha256 = "sha256-...";
  })
];
```

## Creating Patches

### Generating Patch Files

1. Clone the repository:
   ```bash
   git clone https://gitlab.freedesktop.org/wayland/wayland
   cd wayland
   ```

2. Make your changes:
   ```bash
   # Edit files...
   git add -A
   git commit -m "iOS: Remove Linux-specific syscalls"
   ```

3. Generate the patch:
   ```bash
   git format-patch -1 HEAD
   # Or for a simple diff:
   git diff > ../patches/wayland/ios-remove-linux-syscalls.patch
   ```

### Testing Patches

Patches are automatically tested when building the dependency:

```bash
# Build for iOS
nix build .#wayland-ios

# Build for macOS
nix build .#wayland-macos

# Build for Android
nix build .#wayland-android
```

## Platform-Specific Considerations

### iOS
- Remove Linux-specific syscalls (`signalfd`, `timerfd`)
- Use epoll-shim or kqueue alternatives
- Ensure proper Metal/Vulkan integration

### macOS
- Use epoll-shim for epoll compatibility
- Disable Linux-specific GPU paths (DMA-BUF, VAAPI)
- Integrate with Metal/Vulkan via Kosmickrisp

### Android
- Remove Linux syscalls not in Bionic libc
- Integrate with Android's gralloc/DMA-BUF system
- Handle Android-specific EGL/Vulkan integration

## Current Patches

### Wayland
- **ios-remove-linux-syscalls.patch**: Removes `signalfd`/`timerfd` for iOS
- **macos-epoll-shim.patch**: Integrates epoll-shim for macOS
- **android-remove-linux-syscalls.patch**: Removes unsupported syscalls for Android

### Waypipe
- **ios-disable-linux-gpu.patch**: Disables DMA-BUF/VAAPI on iOS
- **macos-disable-linux-gpu.patch**: Disables DMA-BUF/VAAPI on macOS
- **android-gralloc-support.patch**: Adds Android gralloc integration

### Kosmickrisp-Vulkan
- **ios-metal-integration.patch**: iOS Metal backend integration
- **macos-metal-integration.patch**: macOS Metal backend integration

## Notes

- All patch files are currently placeholders. Replace them with actual patches as you develop them.
- Patches are applied in the order they appear in the `patches` array.
- Use `postPatch` for simple text substitutions that don't warrant a full patch file.
- Consider upstreaming platform-agnostic patches to the original projects when possible.
