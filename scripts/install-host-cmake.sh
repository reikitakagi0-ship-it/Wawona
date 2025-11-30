#!/bin/bash

# install-host-cmake.sh
# Builds CMake from source for the host system

set -e
set -o pipefail

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMAKE_DIR="${ROOT_DIR}/dependencies/cmake"
INSTALL_DIR="${ROOT_DIR}/build/ios-bootstrap"
BUILD_DIR="${CMAKE_DIR}/build"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Clone CMake if not exists
if [ ! -d "${CMAKE_DIR}" ]; then
    echo "Cloning CMake..."
    git clone https://github.com/Kitware/CMake.git "${CMAKE_DIR}"
fi

cd "${CMAKE_DIR}"

# Checkout a stable version (latest stable release)
echo "Checking out stable CMake version..."
git fetch --tags
# Get the latest stable version tag
LATEST_TAG=$(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
git checkout "${LATEST_TAG}" || git checkout master

# Configure and build CMake using bootstrap script
echo "Configuring CMake for host build system..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Bootstrap CMake (CMake builds itself)
# Use system compiler (clang) and build a minimal CMake
../bootstrap \
    --prefix="${INSTALL_DIR}" \
    --parallel=$(sysctl -n hw.ncpu) \
    --no-qt-gui \
    --no-system-libs \
    --no-system-jsoncpp \
    --no-system-libarchive \
    --no-system-curl \
    --no-system-expat \
    --no-system-zlib \
    --no-system-bzip2 \
    --no-system-liblzma \
    --no-system-nghttp2 \
    --no-system-zstd \
    --no-system-libuv \
    --no-system-jsoncpp \
    --no-system-libarchive

# Build CMake
echo "Building CMake..."
make -j$(sysctl -n hw.ncpu)

# Install CMake
echo "Installing CMake..."
make install

echo "Success! CMake installed to ${INSTALL_DIR}"
echo "CMake version: $(${INSTALL_DIR}/bin/cmake --version | head -1)"

