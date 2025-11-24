#!/bin/bash

# install-wayland-ios.sh
# Cross-compiles Wayland for iOS Simulator

set -e
set -o pipefail

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
pkg-config = ['pkg-config']

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
# scanner=false: Don't build scanner for iOS (it's a build tool, not a runtime library)
# Meson will automatically find and use a native wayland-scanner when cross-compiling
# We need a native scanner available (from Homebrew or macOS Wayland build)

if ! command -v wayland-scanner >/dev/null; then
    echo "Error: wayland-scanner not found in PATH."
    echo "Please install wayland-scanner:"
    echo "  brew install wayland"
    echo "Or run 'make wayland' first to build it from source."
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
    -Dscanner=false

# Build
echo "Building Wayland for iOS..."
meson compile -C "${BUILD_DIR}"

# Install
echo "Installing Wayland to ${INSTALL_DIR}..."
meson install -C "${BUILD_DIR}"

# Remove any wayland-scanner files that might have been installed (we don't build scanner for iOS)
# These are build tools, not runtime libraries
rm -f "${INSTALL_DIR}/bin/wayland-scanner" 2>/dev/null || true
rm -f "${INSTALL_DIR}/lib/pkgconfig/wayland-scanner.pc" 2>/dev/null || true

echo "Success! Wayland installed to ${INSTALL_DIR}"
