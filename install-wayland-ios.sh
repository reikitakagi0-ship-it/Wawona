#!/bin/bash

# install-wayland-ios.sh
# Cross-compiles Wayland for iOS Simulator

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYLAND_DIR="${ROOT_DIR}/wayland"
BUILD_DIR="${WAYLAND_DIR}/build-ios"
INSTALL_DIR="${ROOT_DIR}/ios-install"
CROSS_FILE="${WAYLAND_DIR}/cross-ios.txt"

# SDK Path
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "Using SDK: ${SDK_PATH}"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Clone Wayland if not exists
if [ ! -d "${WAYLAND_DIR}" ]; then
    echo "Cloning Wayland..."
    git clone https://gitlab.freedesktop.org/wayland/wayland.git "${WAYLAND_DIR}"
fi

cd "${WAYLAND_DIR}"

# Create Meson cross file
cat > "${CROSS_FILE}" <<EOF
[binaries]
c = ['clang']
cpp = ['clang++']
objc = ['clang']
objcpp = ['clang++']
ar = ['ar']
strip = ['strip']
pkgconfig = ['pkg-config']

[properties]
# sys_root = '${SDK_PATH}'  <-- Removed to prevent pkg-config path mangling


[built-in options]
# Note: -Werror not included here for third-party dependencies which may have warnings
# Wawona code uses -Werror via CMakeLists.txt
c_args = ['-arch', 'arm64', '-isysroot', '${SDK_PATH}', '-mios-simulator-version-min=15.0', '-Wall', '-Wextra', '-Wpedantic']
cpp_args = ['-arch', 'arm64', '-isysroot', '${SDK_PATH}', '-mios-simulator-version-min=15.0', '-Wall', '-Wextra', '-Wpedantic']
c_link_args = ['-arch', 'arm64', '-isysroot', '${SDK_PATH}', '-mios-simulator-version-min=15.0']
cpp_link_args = ['-arch', 'arm64', '-isysroot', '${SDK_PATH}', '-mios-simulator-version-min=15.0']

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

echo "Created cross-file at ${CROSS_FILE}"

# Configure
echo "Configuring Wayland for iOS..."
rm -rf "${BUILD_DIR}"

# We need to disable documentation and tests
# libraries=true is default
# scanner=true is default, but we need a native scanner for the build machine (macOS)
# Meson handles native scanner automatically if we are cross compiling?
# Actually, for cross compilation, we usually need a native scanner installed.
# Assuming 'wayland-scanner' is in PATH from the macOS install (make wayland).

if ! command -v wayland-scanner >/dev/null; then
    echo "Error: wayland-scanner not found in PATH."
    echo "Please run 'make wayland' first to install the host tools."
    exit 1
fi

# Set PKG_CONFIG_PATH to find our local libffi and Homebrew dependencies
export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:/opt/homebrew/lib/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"


meson setup "${BUILD_DIR}" \
    --cross-file "${CROSS_FILE}" \
    --prefix "${INSTALL_DIR}" \
    -Ddocumentation=false \
    -Dtests=false \
    -Dlibraries=true \
    -Dscanner=true

# Build
echo "Building Wayland for iOS..."
meson compile -C "${BUILD_DIR}"

# Install
echo "Installing Wayland to ${INSTALL_DIR}..."
meson install -C "${BUILD_DIR}"

echo "Success! Wayland installed to ${INSTALL_DIR}"
