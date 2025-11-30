#!/bin/bash

# install-harfbuzz.sh
# Unified script to build HarfBuzz for macOS (native) or iOS Simulator

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
HARFBUZZ_DIR="${ROOT_DIR}/dependencies/harfbuzz"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${HARFBUZZ_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/build/ios-install"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
    export CXXFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
    
    MESON_EXTRA_ARGS=(
        "--cross-file" "${CROSS_FILE}"
        "-Dcpp_args=-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
    )
    
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${HARFBUZZ_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/build/macos-install"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
    export CFLAGS="-fPIC"
    export CXXFLAGS="-fPIC"
    MESON_EXTRA_ARGS=()
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${HARFBUZZ_DIR}" ]; then
    echo "Error: harfbuzz not found"
    exit 1
fi

cd "${HARFBUZZ_DIR}"

echo "Configuring HarfBuzz..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Dtests=disabled \
    -Ddocs=disabled \
    -Dcairo=disabled \
    -Dglib=disabled \
    -Dicu=disabled \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building HarfBuzz..."
# Patch build.ninja for iOS to remove macOS SDK paths if present
if [ "${PLATFORM}" == "ios" ] && [ -f "${BUILD_DIR}/build.ninja" ]; then
    sed -i '' 's|-I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include||g' "${BUILD_DIR}/build.ninja"
fi

ninja -C "${BUILD_DIR}"

echo "Installing HarfBuzz..."
ninja -C "${BUILD_DIR}" install

echo "Success! HarfBuzz installed to ${INSTALL_DIR}"

