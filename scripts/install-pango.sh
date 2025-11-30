#!/bin/bash

# install-pango.sh
# Unified script to build Pango for macOS (native) or iOS Simulator

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
PANGO_DIR="${ROOT_DIR}/dependencies/pango"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${PANGO_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/build/ios-install"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    MESON_EXTRA_ARGS=("--cross-file" "${CROSS_FILE}")
    
    # iOS Patching
    if [ -d "${PANGO_DIR}" ]; then
        cd "${PANGO_DIR}"
        
        # Patch pango meson.build to disable appleframeworks dependency for iOS
        # Pango tries to link CoreText which we want to disable/control or cross-compilation issues
        echo "Patching pango meson.build for iOS compatibility..."
        python3 -c "
import os
if os.path.exists('meson.build'):
    with open('meson.build', 'r') as f:
        lines = f.readlines()
    patched = False
    for i, line in enumerate(lines):
        if \"has_core_text = cc.links\" in line and \"CoreText\" in line:
            lines[i] = \"  has_core_text = false  # CoreText disabled for iOS cross-compilation\n\"
            patched = True
        elif \"pango_deps += dependency('appleframeworks'\" in line and \"# Disabled for iOS\" not in line:
            lines[i] = \"# \" + line.rstrip() + \"  # Disabled for iOS\n\"
            patched = True
    if patched:
        with open('meson.build', 'w') as f:
            f.writelines(lines)
        print('Patched pango meson.build')
"
    fi
    
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${PANGO_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/build/macos-install"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
    MESON_EXTRA_ARGS=()
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${PANGO_DIR}" ]; then
    echo "Error: pango not found"
    exit 1
fi

cd "${PANGO_DIR}"

echo "Configuring Pango..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Ddocumentation=false \
    -Dintrospection=disabled \
    -Dfontconfig=enabled \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building Pango..."
if [ "${PLATFORM}" == "ios" ]; then
    # Build only libraries, skip utilities and tests that fail on iOS
    ninja -C "${BUILD_DIR}" pango/libpango-1.0.a pango/libpangocairo-1.0.a pango/libpangoft2-1.0.a || {
        echo "Partial build failed, trying full build to see errors..."
        ninja -C "${BUILD_DIR}" || exit 1
    }
else
    ninja -C "${BUILD_DIR}"
fi

echo "Installing Pango..."
if [ "${PLATFORM}" == "ios" ]; then
    ninja -C "${BUILD_DIR}" install 2>&1 | grep -v "pango-view\|pango-list\|pango-segmentation\|test" || {
        # Manual install fallback
        if [ -f "${BUILD_DIR}/pango/libpango-1.0.a" ]; then
            echo "Installing Pango libraries manually..."
            mkdir -p "${INSTALL_DIR}/lib" "${INSTALL_DIR}/include/pango-1.0/pango"
            cp "${BUILD_DIR}/pango/libpango-1.0.a" "${INSTALL_DIR}/lib/" || true
            cp "${BUILD_DIR}/pango/libpangocairo-1.0.a" "${INSTALL_DIR}/lib/" 2>/dev/null || true
            cp "${BUILD_DIR}/pango/libpangoft2-1.0.a" "${INSTALL_DIR}/lib/" 2>/dev/null || true
            cp pango/*.h "${INSTALL_DIR}/include/pango-1.0/pango/" 2>/dev/null || true
            if [ -f "${BUILD_DIR}/meson-private/pango.pc" ]; then
                mkdir -p "${INSTALL_DIR}/lib/pkgconfig"
                cp "${BUILD_DIR}/meson-private/pango.pc" "${INSTALL_DIR}/lib/pkgconfig/" || true
                cp "${BUILD_DIR}/meson-private/pangocairo.pc" "${INSTALL_DIR}/lib/pkgconfig/" 2>/dev/null || true
                cp "${BUILD_DIR}/meson-private/pangoft2.pc" "${INSTALL_DIR}/lib/pkgconfig/" 2>/dev/null || true
            fi
        else
            exit 1
        fi
    }
else
    ninja -C "${BUILD_DIR}" install
fi

echo "Success! Pango installed to ${INSTALL_DIR}"

