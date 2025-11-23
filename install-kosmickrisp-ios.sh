#!/bin/bash

# install-kosmickrisp-ios.sh
# Cross-compiles KosmicKrisp (Mesa) for iOS Simulator

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOSMICKRISP_DIR="${ROOT_DIR}/kosmickrisp"
INSTALL_DIR="${ROOT_DIR}/ios-install"
CROSS_FILE="${ROOT_DIR}/wayland/cross-ios.txt"

# SDK Path
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "Using SDK: ${SDK_PATH}"

# Create install directory
mkdir -p "${INSTALL_DIR}"

cd "${KOSMICKRISP_DIR}"

# Set PKG_CONFIG_PATH - prioritize iOS-installed libraries
# Only include iOS-install paths to avoid finding macOS libraries
export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig"
# Also set PKG_CONFIG_LIBDIR to prevent pkg-config from searching default paths
export PKG_CONFIG_LIBDIR="${INSTALL_DIR}/lib/pkgconfig"

# Ensure Homebrew bison is in PATH (needed for Mesa build)
export PATH="/opt/homebrew/opt/bison/bin:$PATH"
# Ensure native wayland-scanner is found before iOS-installed one (build tools must be native)
# Remove iOS-install/bin from PATH temporarily to avoid finding iOS wayland-scanner
# Save original PATH and remove ios-install/bin
ORIG_PATH="$PATH"
export PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:/usr/local/bin:/usr/bin:/bin"

# Find LLVM config for iOS cross-compilation
LLVM_CONFIG_PATH=""
if [ -f "/opt/homebrew/opt/llvm/bin/llvm-config" ]; then
    LLVM_CONFIG_PATH="/opt/homebrew/opt/llvm/bin/llvm-config"
elif [ -f "/usr/local/opt/llvm/bin/llvm-config" ]; then
    LLVM_CONFIG_PATH="/usr/local/opt/llvm/bin/llvm-config"
elif command -v llvm-config >/dev/null 2>&1; then
    LLVM_CONFIG_PATH=$(which llvm-config)
fi

if [ -z "$LLVM_CONFIG_PATH" ] || [ ! -f "$LLVM_CONFIG_PATH" ]; then
    echo "Error: llvm-config not found. LLVM is required for KosmicKrisp build."
    echo "Install with: brew install llvm"
    exit 1
fi

echo "Using LLVM config: $LLVM_CONFIG_PATH"
export LLVM_CONFIG="$LLVM_CONFIG_PATH"
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"

# Configure
echo "Configuring KosmicKrisp for iOS Simulator..."
rm -rf build-ios

# We need to disable some things that might not work on iOS
# We enable zink and kosmickrisp
# We enable EGL and Wayland platform
# We disable GLX, GBM (unless we have it?), etc.
# We need to point to MoltenVK if required.
# Assuming kosmickrisp driver handles Metal interaction.

# Find MoltenVK directory
MOLTENVK_DIR=""
if [ -d "$(brew --prefix molten-vk 2>/dev/null)" ]; then
    MOLTENVK_DIR=$(brew --prefix molten-vk)
elif [ -d "/opt/homebrew/opt/molten-vk" ]; then
    MOLTENVK_DIR="/opt/homebrew/opt/molten-vk"
elif [ -d "/usr/local/opt/molten-vk" ]; then
    MOLTENVK_DIR="/usr/local/opt/molten-vk"
fi

if [ -z "$MOLTENVK_DIR" ]; then
    echo "Warning: MoltenVK not found. Installing..."
    brew install molten-vk || {
        echo "Error: Failed to install MoltenVK"
        echo "Install with: brew install molten-vk"
        exit 1
    }
    MOLTENVK_DIR=$(brew --prefix molten-vk)
fi

echo "Using MoltenVK directory: $MOLTENVK_DIR"

# For iOS, we build KosmicKrisp Vulkan driver but disable Zink (OpenGL ES)
# iOS Simulator SDK doesn't have Metal Vulkan extensions needed by Zink
# We can still use Vulkan directly via KosmicKrisp
# Configure Meson with iOS-specific overrides
# Note: iOS doesn't have endian.h, but u_endian.h handles this via __APPLE__ check
# We need to ensure zstd headers are found for target compilation
# Link args are set in cross file, but host tools should use host libraries
meson setup build-ios \
    --cross-file "${CROSS_FILE}" \
    --prefix "${INSTALL_DIR}" \
    -Dplatforms=wayland \
    -Dvulkan-drivers=kosmickrisp \
    -Dgallium-drivers= \
    -Dglx=disabled \
    -Dgbm=disabled \
    -Degl=disabled \
    -Dopengl=false \
    -Dgles1=disabled \
    -Dgles2=disabled \
    -Dllvm=enabled \
    -Dshared-llvm=disabled \
    -Dmoltenvk-dir="${MOLTENVK_DIR}" \
    -Dbuild-tests=false \
    -Dmesa-clc=auto \
    -Dc_args="-I${INSTALL_DIR}/include -arch arm64 -target arm64-apple-ios16.0-simulator -isysroot ${SDK_PATH} -mios-simulator-version-min=16.0" \
    -Dcpp_args="-I${INSTALL_DIR}/include -arch arm64 -target arm64-apple-ios16.0-simulator -isysroot ${SDK_PATH} -mios-simulator-version-min=16.0" \
    -Dobjc_args="-I${INSTALL_DIR}/include -arch arm64 -target arm64-apple-ios16.0-simulator -isysroot ${SDK_PATH} -mios-simulator-version-min=16.0" \
    -Dobjcpp_args="-I${INSTALL_DIR}/include -arch arm64 -target arm64-apple-ios16.0-simulator -isysroot ${SDK_PATH} -mios-simulator-version-min=16.0"

# Build
echo "Building KosmicKrisp..."
meson compile -C build-ios

# Install
echo "Installing KosmicKrisp..."
meson install -C build-ios

echo "Success! KosmicKrisp installed to ${INSTALL_DIR}"
