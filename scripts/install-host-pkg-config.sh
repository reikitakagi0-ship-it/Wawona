#!/bin/bash

# install-host-pkg-config.sh
# Builds pkg-config from source for the host system

set -e
set -o pipefail

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_CONFIG_DIR="${ROOT_DIR}/dependencies/pkg-config"
INSTALL_DIR="${ROOT_DIR}/build/ios-bootstrap"
BUILD_DIR="${PKG_CONFIG_DIR}/build"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Download pkg-config release tarball if not exists
if [ ! -d "${PKG_CONFIG_DIR}" ]; then
    echo "Downloading pkg-config..."
    PKG_CONFIG_VERSION="0.29.2"
    curl -L -o pkg-config.tar.gz "https://pkg-config.freedesktop.org/releases/pkg-config-${PKG_CONFIG_VERSION}.tar.gz"
    tar -xzf pkg-config.tar.gz
    mv "pkg-config-${PKG_CONFIG_VERSION}" "${PKG_CONFIG_DIR}"
    rm pkg-config.tar.gz
fi

cd "${PKG_CONFIG_DIR}"

# Release tarball already has configure script
if [ ! -f "configure" ]; then
    echo "Error: configure script not found in ${PKG_CONFIG_DIR}"
    exit 1
fi

# Configure and build pkg-config
echo "Configuring pkg-config for host build system..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# pkg-config uses autotools
# Use system glib instead of internal glib to avoid build issues
# Set CFLAGS to disable specific warnings that are treated as errors or clutter output
# These warnings come from glib (pkg-config's dependency) and are harmless
export CFLAGS="-Wall -Wextra -Wno-error -O2 \
  -Wno-unused-parameter \
  -Wno-int-conversion \
  -Wno-cast-function-type \
  -Wno-deprecated-declarations \
  -Wno-sign-compare \
  -Wno-missing-field-initializers \
  -Wno-unused-value \
  -Wno-unused-but-set-variable \
  -Wno-null-pointer-subtraction \
  -Wno-void-pointer-to-enum-cast \
  -Wno-unused-function \
  -Wno-return-type"
../configure \
    --prefix="${INSTALL_DIR}" \
    --with-internal-glib \
    --disable-host-tool \
    --with-pc-path="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig" \
    --enable-indirect-deps

# Build
echo "Building pkg-config..."
make -j$(sysctl -n hw.ncpu)

# Install
echo "Installing pkg-config..."
make install

echo "Success! pkg-config installed to ${INSTALL_DIR}"
echo "pkg-config version: $(${INSTALL_DIR}/bin/pkg-config --version)"

