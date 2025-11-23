#!/bin/bash

# install-epoll-shim-ios.sh
# Cross-compiles epoll-shim for iOS Simulator

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EPOLL_SHIM_DIR="${ROOT_DIR}/epoll-shim"
INSTALL_DIR="${ROOT_DIR}/ios-install"

# SDK Path
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "Using SDK: ${SDK_PATH}"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Clone epoll-shim if not exists
if [ ! -d "${EPOLL_SHIM_DIR}" ]; then
    echo "Cloning epoll-shim..."
    git clone https://github.com/jiixyj/epoll-shim.git "${EPOLL_SHIM_DIR}"
fi

cd "${EPOLL_SHIM_DIR}"

# Configure
echo "Configuring epoll-shim for iOS Simulator..."
rm -rf build
mkdir build
cd build

# CMake cross-compilation
# Enable warnings and treat them as errors (matching Wawona's build requirements)
# Note: We suppress -Wpedantic warnings for function pointer conversions (dlsym pattern)
# which are false positives for dlsym usage patterns
cmake .. \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    --log-level=WARNING \
    -DBUILD_TESTING=OFF \
    -DALLOWS_ONESHOT_TIMERS_WITH_TIMEOUT_ZERO_EXITCODE=0 \
    -DENABLE_COMPILER_WARNINGS=ON \
    -DCMAKE_C_FLAGS="-Wall -Wextra -Werror -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wmissing-declarations -Wuninitialized -Winit-self -Wpointer-arith -Wcast-qual -Wwrite-strings -Wconversion -Wsign-conversion -Wformat=2 -Wformat-security -Wundef -Wshadow -Wstrict-overflow=5 -Wswitch-default -Wswitch-enum -Wunreachable-code -Wfloat-equal -Wstack-protector -fstack-protector-strong -fPIC -Werror=incompatible-pointer-types-discards-qualifiers -Wno-pedantic"


# Build
echo "Building epoll-shim..."
make -j$(sysctl -n hw.ncpu)

# Install
echo "Installing epoll-shim..."
make install

echo "Success! epoll-shim installed to ${INSTALL_DIR}"
