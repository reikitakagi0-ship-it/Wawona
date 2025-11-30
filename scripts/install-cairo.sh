#!/bin/bash

# install-cairo.sh
# Unified script to build Cairo for macOS (native) or iOS Simulator

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
CAIRO_DIR="${ROOT_DIR}/dependencies/cairo"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${CAIRO_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/build/ios-install"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    
    MESON_EXTRA_ARGS=(
        "--cross-file" "${CROSS_FILE}"
        "-Dquartz=disabled"
    )
    
    # iOS-specific patching
    if [ -f "${CAIRO_DIR}/src/cairo-ps-surface.c" ] && grep -q "^static char \*ctime_r" "${CAIRO_DIR}/src/cairo-ps-surface.c"; then
        echo "Patching cairo-ps-surface.c for iOS compatibility..."
        sed -i '' 's/^static char \*ctime_r(/static char \*cairo_ctime_r(/g' "${CAIRO_DIR}/src/cairo-ps-surface.c"
        sed -i '' 's/ctime_r(/cairo_ctime_r(/g' "${CAIRO_DIR}/src/cairo-ps-surface.c"
        echo "✓ Patched cairo-ps-surface.c"
    fi
    
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${CAIRO_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/build/macos-install"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
    MESON_EXTRA_ARGS=(
        "-Dquartz=enabled"
    )
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${CAIRO_DIR}" ]; then
    echo "Error: cairo not found"
    exit 1
fi

cd "${CAIRO_DIR}"

echo "Configuring Cairo..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Dtests=disabled \
    -Dgtk2-utils=disabled \
    -Dspectre=disabled \
    -Dxlib=disabled \
    -Dxlib-xcb=disabled \
    -Dxcb=disabled \
    -Dfreetype=enabled \
    -Dfontconfig=enabled \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building Cairo..."
# Build only the library, skip utility executables that might fail on iOS
if [ "${PLATFORM}" == "ios" ]; then
    ninja -C "${BUILD_DIR}" src/libcairo.a util/cairo-trace/libcairo-trace.a util/cairo-fdr/libcairo-fdr.a || {
        echo "Build failed, checking output..."
        exit 1
    }
else
    ninja -C "${BUILD_DIR}"
fi

echo "Installing Cairo..."
if [ "${PLATFORM}" == "ios" ]; then
    # Install only the library and headers, skip utility executables
    ninja -C "${BUILD_DIR}" install 2>&1 | grep -v "csi-replay\|csi-exec\|csi-trace" || {
        # If install fails due to utilities, manually install what we need
        if [ -f "${BUILD_DIR}/src/libcairo.a" ]; then
            echo "Installing Cairo library manually (utilities failed, which is OK for iOS)..."
            mkdir -p "${INSTALL_DIR}/lib" "${INSTALL_DIR}/include/cairo"
            cp "${BUILD_DIR}/src/libcairo.a" "${INSTALL_DIR}/lib/" || true
            cp src/cairo.h src/cairo-*.h "${INSTALL_DIR}/include/cairo/" 2>/dev/null || true
            cp "${BUILD_DIR}/src/cairo-features.h" "${INSTALL_DIR}/include/cairo/" 2>/dev/null || true
            if [ -f "${BUILD_DIR}/meson-private/cairo.pc" ]; then
                mkdir -p "${INSTALL_DIR}/lib/pkgconfig"
                cp "${BUILD_DIR}/meson-private/cairo.pc" "${INSTALL_DIR}/lib/pkgconfig/" || true
            fi
            
            # Create cairo-ft.pc and cairo-fc.pc for Pango compatibility
            CAIRO_LIBS=$(PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig" pkg-config --libs cairo)
            cat > "${INSTALL_DIR}/lib/pkgconfig/cairo-ft.pc" << CAIRO_FT_PC_EOF
prefix=${INSTALL_DIR}
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: cairo-ft
Description: FreeType font backend for cairo graphics library
Version: 1.18.5
Requires: cairo freetype2 >= 23.0.17 fontconfig >= 2.13.0
Requires.private: cairo freetype2 fontconfig
Libs: ${CAIRO_LIBS}
Cflags: -I\${includedir}/cairo
CAIRO_FT_PC_EOF

            cat > "${INSTALL_DIR}/lib/pkgconfig/cairo-fc.pc" << CAIRO_FC_PC_EOF
prefix=${INSTALL_DIR}
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: cairo-fc
Description: Fontconfig font backend for cairo graphics library
Version: 1.18.5
Requires: cairo fontconfig >= 2.13.0
Libs:
Cflags: -I\${includedir}/cairo
CAIRO_FC_PC_EOF
        else
            exit 1
        fi
    }
else
    ninja -C "${BUILD_DIR}" install
    # Create compat pkg-config files for macOS too if missing
    if [ ! -f "${INSTALL_DIR}/lib/pkgconfig/cairo-ft.pc" ]; then
        cp "${INSTALL_DIR}/lib/pkgconfig/cairo.pc" "${INSTALL_DIR}/lib/pkgconfig/cairo-ft.pc"
    fi
    if [ ! -f "${INSTALL_DIR}/lib/pkgconfig/cairo-fc.pc" ]; then
        cp "${INSTALL_DIR}/lib/pkgconfig/cairo.pc" "${INSTALL_DIR}/lib/pkgconfig/cairo-fc.pc"
    fi
fi

echo "Success! Cairo installed to ${INSTALL_DIR}"

