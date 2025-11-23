#!/bin/bash

# install-lz4-ios.sh
# Cross-compiles lz4 for iOS Simulator

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LZ4_DIR="${ROOT_DIR}/lz4"
INSTALL_DIR="${ROOT_DIR}/ios-install"

# SDK Path
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "Using SDK: ${SDK_PATH}"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Clone lz4 if not exists
if [ ! -d "${LZ4_DIR}" ]; then
    echo "Cloning lz4..."
    git clone https://github.com/lz4/lz4.git "${LZ4_DIR}"
    cd "${LZ4_DIR}"
    git checkout v1.9.4
else
    cd "${LZ4_DIR}"
fi

# Build
echo "Building lz4 for iOS Simulator..."
export CC="xcrun -sdk iphonesimulator clang"
export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
export LDFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"

# lz4 Makefile supports standard variables
make clean
make -j$(sysctl -n hw.ncpu) lib

# Install
# lz4 Makefile install target might need tweaks, but let's try
make install PREFIX="${INSTALL_DIR}"

echo "Success! lz4 installed to ${INSTALL_DIR}"
