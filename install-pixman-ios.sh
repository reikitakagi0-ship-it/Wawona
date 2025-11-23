#!/bin/bash

# install-pixman-ios.sh
# Cross-compiles pixman for iOS Simulator using Meson

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIXMAN_DIR="${ROOT_DIR}/pixman"
BUILD_DIR="${PIXMAN_DIR}/build-ios"
INSTALL_DIR="${ROOT_DIR}/ios-install"
CROSS_FILE="${ROOT_DIR}/wayland/cross-ios.txt"

# SDK Path
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "Using SDK: ${SDK_PATH}"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Clone pixman if not exists
if [ ! -d "${PIXMAN_DIR}" ]; then
    echo "Cloning pixman..."
    git clone https://gitlab.freedesktop.org/pixman/pixman.git "${PIXMAN_DIR}"
fi

cd "${PIXMAN_DIR}"

# Checkout stable version if not already checked out
if [ -z "$(git describe --tags --exact-match HEAD 2>/dev/null)" ]; then
    echo "Checking out stable version..."
    git checkout -q pixman-0.46.4 2>/dev/null || git checkout -q 0.46.4 2>/dev/null || true
fi

# Configure for iOS Simulator using Meson
echo "Configuring pixman for iOS Simulator..."

# Set PKG_CONFIG_PATH for iOS-installed libraries
export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"

# Use Meson with cross-file
rm -rf "${BUILD_DIR}"
meson setup "${BUILD_DIR}" \
    --cross-file "${CROSS_FILE}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Dgtk=disabled \
    -Dlibpng=disabled \
    -Dtests=disabled \
    -Dopenmp=disabled

# Build
echo "Building pixman..."
ninja -C "${BUILD_DIR}"

# Install
echo "Installing pixman..."
ninja -C "${BUILD_DIR}" install

echo "Success! pixman installed to ${INSTALL_DIR}"
