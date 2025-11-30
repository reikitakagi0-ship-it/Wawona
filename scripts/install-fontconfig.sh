#!/bin/bash

# install-fontconfig.sh
# Unified script to build FontConfig for macOS (native) or iOS Simulator

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
FONTCONFIG_DIR="${ROOT_DIR}/dependencies/fontconfig"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${FONTCONFIG_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/build/ios-install"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    
    MESON_EXTRA_ARGS=(
        "--cross-file" "${CROSS_FILE}"
    )
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${FONTCONFIG_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/build/macos-install"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
    MESON_EXTRA_ARGS=()
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${FONTCONFIG_DIR}" ]; then
    echo "Error: fontconfig not found"
    exit 1
fi

cd "${FONTCONFIG_DIR}"

echo "Configuring FontConfig..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Dtests=disabled \
    -Dtools=disabled \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building FontConfig..."
ninja -C "${BUILD_DIR}"

echo "Installing FontConfig..."
ninja -C "${BUILD_DIR}" install

echo "Success! FontConfig installed to ${INSTALL_DIR}"

