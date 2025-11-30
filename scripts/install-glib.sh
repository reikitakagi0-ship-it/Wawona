#!/bin/bash

# install-glib.sh
# Unified script to build GLib for macOS (native) or iOS Simulator

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
GLIB_DIR="${ROOT_DIR}/dependencies/glib"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${GLIB_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/build/ios-install"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    
    MESON_EXTRA_ARGS=(
        "--cross-file" "${CROSS_FILE}"
    )
    
    # Patch gnulib meson.build to disable frexpl check for iOS
    GNULIB_MESON="${GLIB_DIR}/glib/gnulib/meson.build"
    if [ -f "${GNULIB_MESON}" ] && ! grep -q "warning.*frexpl.*not available on iOS" "${GNULIB_MESON}" 2>/dev/null; then
        echo "Patching ${GNULIB_MESON} for iOS compatibility..."
        # Simple robust python patcher
        python3 -c "
import sys
import re
try:
    with open('${GNULIB_MESON}', 'r') as f:
        content = f.read()
    patterns = [
        (r\"error\s*\(\s*['\\\"]frexpl\(\) is missing or broken beyond repair, and we have nothing to replace it with['\\\"]\s*\)\", \"warning ('frexpl() not available on iOS, continuing without it')\"),
    ]
    patched = False
    for pattern, replacement in patterns:
        if re.search(pattern, content):
            content = re.sub(pattern, replacement, content)
            patched = True
            break
    if patched:
        with open('${GNULIB_MESON}', 'w') as f:
            f.write(content)
        print('Patched glib/gnulib/meson.build')
except Exception as e:
    print(f'Error patching: {e}')
"
    fi
    
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${GLIB_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/build/macos-install"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
    MESON_EXTRA_ARGS=()
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${GLIB_DIR}" ]; then
    echo "Error: glib not found"
    exit 1
fi

cd "${GLIB_DIR}"

# Checkout stable
if [ -z "$(git describe --tags --exact-match HEAD 2>/dev/null)" ]; then
    echo "Checking out stable version..."
    git fetch --tags
    git checkout -q $(git tag | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1) 2>/dev/null || true
fi

echo "Configuring GLib..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Dtests=false \
    -Dman-pages=disabled \
    -Ddocumentation=false \
    -Dnls=disabled \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building GLib..."
ninja -C "${BUILD_DIR}"

echo "Installing GLib..."
ninja -C "${BUILD_DIR}" install

echo "Success! GLib installed to ${INSTALL_DIR}"

