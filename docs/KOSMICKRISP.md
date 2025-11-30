# KosmicKrisp Driver for macOS

## Overview

KosmicKrisp is a Vulkan driver for macOS that provides Vulkan conformance on Apple Silicon and Intel Macs. It's based on the panfrost driver (originally for ARM Mali GPUs) and has been adapted for Apple Silicon GPUs. The driver translates Vulkan API calls to Apple's Metal framework, enabling Vulkan applications to run natively on macOS.

## Purpose

This driver enables:
- **Vulkan support** on macOS (native Vulkan ICD, not via MoltenVK)
- **DMA-BUF support** via Vulkan for waypipe
- **Video encoding/decoding** via Vulkan for waypipe video features
- **Hardware acceleration** on Apple Silicon Macs
- **Vulkan 1.3 conformance** for graphics operations

## Integration with Waypipe

With KosmicKrisp installed, waypipe can use:
- `dmabuf` feature - DMA-BUF transfers via Vulkan (requires Vulkan SDK headers)
- `video` feature - Hardware-accelerated video encoding/decoding via Vulkan
- Full Vulkan conformance for graphics operations

## Repository

KosmicKrisp is part of the Mesa project:
- **Repository**: https://gitlab.freedesktop.org/mesa/mesa.git
- **Mesa Version**: Merged in Mesa 26.0 (October 2025)
- **Developer**: LunarG (sponsored by Google)
- **Driver Name**: `kosmickrisp` (Vulkan driver name in Mesa build system)
- **Purpose**: Vulkan-to-Metal translation layer for macOS, providing Vulkan 1.3 conformance

## Build Instructions

The driver is built and installed via `make kosmickrisp` target in the Makefile.

### Manual Build

If you need to build manually:

```bash
# Clone Mesa repository
git clone https://gitlab.freedesktop.org/mesa/mesa.git kosmickrisp
cd kosmickrisp

# Configure build for macOS with KosmicKrisp driver
meson setup build \
  --prefix=/opt/homebrew \
  -Dplatforms=auto \
  -Dvulkan-drivers=swrast,kosmickrisp \
  -Dgallium-drivers=swrast \
  -Dvulkan-layers=[] \
  -Dtools=[] \
  -Dosmesa=disabled \
  -Dglx=disabled \
  -Degl=enabled \
  -Dgles1=enabled \
  -Dgles2=enabled \
  -Dgallium-drivers=zink \
  -Dgbm=disabled

# Build
ninja -C build

# Install (requires sudo)
sudo ninja -C build install
```

## Dependencies

- **meson** - Build system
- **ninja** - Build tool
- **Vulkan SDK** - For Vulkan headers (optional, but recommended for waypipe video support)
- **Xcode Command Line Tools** - For C/C++ compilation

## Installation Location

After installation, the Vulkan ICD (Installable Client Driver) will be installed to:
- `/opt/homebrew/share/vulkan/icd.d/` - ICD JSON files
- `/opt/homebrew/lib/` - Driver libraries

## Usage with Waypipe

Once KosmicKrisp is installed:

1. **No restart required**: The driver is available immediately after installation (user-space driver, not a kernel extension).

2. **Verify Vulkan is available** (optional):
   ```bash
   # Install Vulkan SDK tools if needed
   brew install vulkan-headers vulkan-loader
   
   # Check if driver is detected
   export VK_ICD_FILENAMES=/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json
   vulkaninfo | grep -i "device name"
   ```

3. **Build waypipe with Vulkan support**:
   ```bash
   make waypipe  # Will auto-detect Vulkan and enable dmabuf + video features
   ```

4. **Use waypipe with dmabuf and video**:
   ```bash
   waypipe --video ssh user@host app
   ```

## Post-Installation Notes

- **No restart required**: Mesa Vulkan drivers are user-space libraries and don't require a system restart.
- **Driver location**: Installed to `/opt/homebrew/lib/libvulkan_kosmickrisp.dylib`
- **ICD file**: `/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json`
- **If issues occur**: If Vulkan applications don't detect the driver, try:
  - Setting `VK_ICD_FILENAMES` environment variable explicitly
  - Restarting the application (not the system)
  - Checking that `/opt/homebrew/lib` is in your library path

## References

- Mesa project: https://www.mesa3d.org/
- Panfrost driver: https://gitlab.freedesktop.org/mesa/mesa/-/tree/main/src/gallium/drivers/panfrost
- Vulkan ICD specification: https://github.com/KhronosGroup/Vulkan-Loader/blob/main/loader/LoaderAndLayerInterface.md

