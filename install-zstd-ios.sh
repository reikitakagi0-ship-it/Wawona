#!/bin/bash

# install-zstd-ios.sh
# Cross-compiles zstd for iOS Simulator

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSTD_DIR="${ROOT_DIR}/zstd"
INSTALL_DIR="${ROOT_DIR}/ios-install"

# SDK Path
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "Using SDK: ${SDK_PATH}"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Clone zstd if not exists
if [ ! -d "${ZSTD_DIR}" ]; then
    echo "Cloning zstd..."
    git clone https://github.com/facebook/zstd.git "${ZSTD_DIR}"
    cd "${ZSTD_DIR}"
    git checkout v1.5.5
else
    cd "${ZSTD_DIR}"
fi

# Build
echo "Building zstd for iOS Simulator..."
export CC="xcrun -sdk iphonesimulator clang"
export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
export LDFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"

# zstd Makefile supports standard variables
make clean
make -j$(sysctl -n hw.ncpu) lib

# Install
make install PREFIX="${INSTALL_DIR}"

# Fix pkg-config file to use correct prefix
if [ -f "${INSTALL_DIR}/lib/pkgconfig/libzstd.pc" ]; then
    sed -i.bak "s|^prefix=.*|prefix=${INSTALL_DIR}|" "${INSTALL_DIR}/lib/pkgconfig/libzstd.pc"
    rm -f "${INSTALL_DIR}/lib/pkgconfig/libzstd.pc.bak"
fi

echo "Success! zstd installed to ${INSTALL_DIR}"
