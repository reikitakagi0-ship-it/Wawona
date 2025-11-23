#!/bin/bash

# install-libffi-ios.sh
# Cross-compiles libffi for iOS Simulator

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBFFI_DIR="${ROOT_DIR}/libffi"
INSTALL_DIR="${ROOT_DIR}/ios-install"

# SDK Path
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "Using SDK: ${SDK_PATH}"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Download libffi release tarball
if [ ! -d "${LIBFFI_DIR}" ]; then
    echo "Downloading libffi..."
    curl -L -o libffi.tar.gz https://github.com/libffi/libffi/releases/download/v3.4.4/libffi-3.4.4.tar.gz
    tar -xzf libffi.tar.gz
    mv libffi-3.4.4 "${LIBFFI_DIR}"
    rm libffi.tar.gz
fi

cd "${LIBFFI_DIR}"

# No need to run autogen.sh for release tarball


# Configure for iOS Simulator (arm64)
echo "Configuring libffi for iOS Simulator..."

# We need to set CFLAGS/LDFLAGS manually for autotools
export CC="xcrun -sdk iphonesimulator clang"
export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fno-asynchronous-unwind-tables"
export LDFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"


./configure \
    --host=aarch64-apple-darwin \
    --prefix="${INSTALL_DIR}" \
    --enable-static \
    --disable-shared \
    --disable-multi-os-directory

# Disable CFI in fficonfig.h to fix assembly error on iOS Simulator
sed -i '' 's/#define HAVE_AS_CFI_PSEUDO_OP 1/#undef HAVE_AS_CFI_PSEUDO_OP/' aarch64-apple-darwin/fficonfig.h


# Build
echo "Building libffi..."

make -j$(sysctl -n hw.ncpu)

# Install
echo "Installing libffi..."
make install

echo "Success! libffi installed to ${INSTALL_DIR}"
