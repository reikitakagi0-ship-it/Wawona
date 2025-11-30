#!/bin/bash

# install-gtk.sh
# Unified script to build GTK+ 3.0 for macOS (native) or iOS Simulator

set -e
set -o pipefail

PLATFORM="macos"

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform) PLATFORM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "Target Platform: ${PLATFORM}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GTK_DIR="${ROOT_DIR}/dependencies/gtk"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${GTK_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/build/ios-install"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    MESON_EXTRA_ARGS=("--cross-file" "${CROSS_FILE}")
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${GTK_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/build/macos-install"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:${INSTALL_DIR}/share/pkgconfig:$PKG_CONFIG_PATH"
    MESON_EXTRA_ARGS=("-Dquartz_backend=true" "-Dx11_backend=false" "-Dwayland_backend=true")
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${GTK_DIR}" ]; then
    echo "Error: gtk not found"
    exit 1
fi

cd "${GTK_DIR}"

# Checkout GTK 3.x branch
if [ -z "$(git branch --show-current | grep gtk-3-24)" ]; then
    git fetch origin
    git checkout -q origin/gtk-3-24 2>/dev/null || git checkout -q $(git tag | grep -E '^3\.[0-9]+\.[0-9]+$' | sort -V | tail -1) 2>/dev/null || true
fi

echo "Configuring GTK+ 3.0..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Dintrospection=disabled \
    -Dmedia-gstreamer=disabled \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building GTK+ 3.0..."
ninja -C "${BUILD_DIR}"

echo "Installing GTK+ 3.0..."
ninja -C "${BUILD_DIR}" install

echo "Success! GTK+ 3.0 installed to ${INSTALL_DIR}"

