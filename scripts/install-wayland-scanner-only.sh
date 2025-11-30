#!/bin/bash

# install-wayland-scanner-only.sh
# Builds only wayland-scanner for host system (build tool)

set -e
set -o pipefail

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAYLAND_DIR="${ROOT_DIR}/dependencies/wayland"
BUILD_DIR="${WAYLAND_DIR}/build-scanner-only"
INSTALL_DIR="${ROOT_DIR}/build/ios-bootstrap"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Clone Wayland if not exists
if [ ! -d "${WAYLAND_DIR}" ]; then
    echo "Cloning Wayland..."
    git clone https://gitlab.freedesktop.org/wayland/wayland.git "${WAYLAND_DIR}"
fi

cd "${WAYLAND_DIR}"

# Checkout stable version
echo "Checking out stable version..."
git fetch --tags
git checkout 1.24.0 || git checkout $(git tag | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)

# Set PKG_CONFIG_PATH to find our local dependencies (host tools)
# Clear cross-compilation PKG_CONFIG paths
unset PKG_CONFIG_LIBDIR
export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig"

# Configure - only build scanner, not libraries
echo "Configuring wayland-scanner for host..."
rm -rf "${BUILD_DIR}"

# Ensure we link against epoll-shim if needed (it might be in the host install already if built)
# But typically wayland-scanner doesn't need epoll-shim, it's just a code generator.
# The issue reported by user is likely about the *target* build or the checks in the scanner build confusing headers.
# The user wants these checks to pass. Since this is a host build (macOS), we need headers.
# Epoll-shim provides sys/timerfd.h, sys/signalfd.h etc. but typically not sys/prctl.h
# macOS simply doesn't have these.

# However, if the USER wants these YES, it implies we need to provide them or fake them.
# But wait, the log shows:
# Checking for function "accept4" : NO
# ...
# This is happening during "Configuring wayland-scanner for host..."

# We need to inject epoll-shim into the HOST build of wayland-scanner if we want those checks to pass on macOS.
# 1. Build epoll-shim for HOST (ios-bootstrap)
# 2. Point meson to it.

# Check if epoll-shim is installed in ios-bootstrap
if [ ! -f "${INSTALL_DIR}/include/libepoll-shim/sys/timerfd.h" ]; then
    echo "Building host epoll-shim for wayland-scanner..."
    "${ROOT_DIR}/scripts/install-epoll-shim.sh" --platform host
fi

export CFLAGS="-I${INSTALL_DIR}/include/libepoll-shim"
export LDFLAGS="-L${INSTALL_DIR}/lib -Wl,-rpath,${INSTALL_DIR}/lib -lepoll-shim"
# pkg-config should handle this if .pc file exists, but manual flags help

# Ensure a valid compiler is found for Meson
# Unset potentially conflicting env vars from parent calls
unset CC
unset CXX
# unset CFLAGS  <-- Don't unset what we just set
# unset CXXFLAGS
# unset LDFLAGS

# Re-apply necessary flags for epoll-shim
# export CFLAGS="-I${INSTALL_DIR}/include/libepoll-shim -L${INSTALL_DIR}/lib" <-- duplicate and wrong
# export LDFLAGS="-L${INSTALL_DIR}/lib -lepoll-shim"

meson setup "${BUILD_DIR}" \
    --prefix "${INSTALL_DIR}" \
    -Ddocumentation=false \
    -Dtests=false \
    -Dlibraries=false \
    -Dscanner=true \
    -Dwerror=false \
    -Dc_args="${CFLAGS}" \
    -Dcpp_args="${CFLAGS}" \
    -Dc_link_args="${LDFLAGS}" \
    -Dcpp_link_args="${LDFLAGS}"

# Build
echo "Building wayland-scanner..."
meson compile -C "${BUILD_DIR}"

# Install
echo "Installing wayland-scanner..."
meson install -C "${BUILD_DIR}"

echo "Success! wayland-scanner installed to ${INSTALL_DIR}/bin/wayland-scanner"
