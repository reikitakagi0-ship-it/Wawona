#!/bin/bash
# Run a single Wayland test client interactively (no timeout, runs until SIGTERM)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Clients are installed to multiple directories
WESTON_BIN_DIR="$PROJECT_ROOT/test-clients/weston/bin"
MINIMAL_BIN_DIR="$PROJECT_ROOT/test-clients/minimal/bin"
DEBUG_BIN_DIR="$PROJECT_ROOT/test-clients/debug/bin"
SYMLINK_BIN_DIR="$PROJECT_ROOT/test-clients/bin"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CLIENT_NAME="$1"

if [ -z "$CLIENT_NAME" ]; then
    echo -e "${RED}✗${NC} Usage: $0 <client-name>"
    echo ""
    echo "Available clients:"
    echo "  wayland-info, wayland-debug"
    echo "  simple-shm, simple-damage"
    echo "  weston-simple-shm, weston-simple-egl, weston-transformed"
    echo "  weston-subsurfaces, weston-simple-damage, weston-simple-touch"
    echo "  weston-eventdemo, weston-keyboard, weston-dnd"
    echo "  weston-cliptest, weston-image, weston-editor"
    exit 1
fi

WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export WAYLAND_DISPLAY

# Check if compositor is running
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}"
SOCKET_PATH="${RUNTIME_DIR}/${WAYLAND_DISPLAY}"

if [ ! -S "$SOCKET_PATH" ]; then
    FOUND_SOCKET=$(find "$RUNTIME_DIR" -name "wayland-*" -type s 2>/dev/null | head -1)
    if [ -n "$FOUND_SOCKET" ] && [ -S "$FOUND_SOCKET" ]; then
        SOCKET_PATH="$FOUND_SOCKET"
        WAYLAND_DISPLAY=$(basename "$FOUND_SOCKET")
        export WAYLAND_DISPLAY
        echo -e "${YELLOW}ℹ${NC} Found Wayland socket: $SOCKET_PATH (using WAYLAND_DISPLAY=$WAYLAND_DISPLAY)"
    else
        echo -e "${RED}✗${NC} Wayland socket not found: $SOCKET_PATH"
        echo -e "${YELLOW}ℹ${NC} Start the compositor first: make run-compositor"
        exit 1
    fi
fi

# Find client binary
CLIENT_PATH=""

# Check in order: symlink dir, weston bin, minimal bin, debug bin
for DIR in "$SYMLINK_BIN_DIR" "$WESTON_BIN_DIR" "$MINIMAL_BIN_DIR" "$DEBUG_BIN_DIR"; do
    if [ -f "$DIR/$CLIENT_NAME" ]; then
        CLIENT_PATH="$DIR/$CLIENT_NAME"
        break
    fi
done

# Also check if it's in PATH
if [ -z "$CLIENT_PATH" ] && command -v "$CLIENT_NAME" &> /dev/null; then
    CLIENT_PATH=$(command -v "$CLIENT_NAME")
fi

if [ -z "$CLIENT_PATH" ]; then
    echo -e "${RED}✗${NC} Client '$CLIENT_NAME' not found"
    echo -e "${YELLOW}ℹ${NC} Build test clients first: make test-clients"
    exit 1
fi

# Handle special client arguments
CLIENT_ARGS=""
case "$CLIENT_NAME" in
    "weston-image")
        # weston-image needs at least one image file argument
        CLIENT_ARGS="--help"
        ;;
esac

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}▶ Running $CLIENT_NAME interactively${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}ℹ${NC} WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
echo -e "${YELLOW}ℹ${NC} Client: $CLIENT_PATH"
echo -e "${YELLOW}ℹ${NC} Press Ctrl+C (SIGTERM) to exit"
echo ""

    # Set up EGL/Mesa environment variables for EGL clients
    if [[ "$CLIENT_NAME" =~ ^(weston-simple-egl|weston-subsurfaces)$ ]]; then
        # Use patched KosmicKrisp EGL library first (if available)
        KOSMICKRISP_BUILD_EGL="$PROJECT_ROOT/kosmickrisp/build/src/egl"
        if [ -f "$KOSMICKRISP_BUILD_EGL/libEGL.1.dylib" ]; then
            export DYLD_LIBRARY_PATH="$KOSMICKRISP_BUILD_EGL:$DYLD_LIBRARY_PATH"
            echo -e "${YELLOW}  ${NC} Using patched KosmicKrisp EGL library from: $KOSMICKRISP_BUILD_EGL"
        fi
        
        # KosmicKrisp paths
        KOSMICKRISP_PREFIX="${KOSMICKRISP_PREFIX:-/opt/homebrew}"
        KOSMICKRISP_LIB="${KOSMICKRISP_PREFIX}/lib"
        KOSMICKRISP_DRI="${KOSMICKRISP_LIB}/dri"
        KOSMICKRISP_ICD="${KOSMICKRISP_PREFIX}/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json"
        
        # Find Vulkan library path (required by Zink)
        VULKAN_LIB_PATH="/opt/homebrew/lib"
        if [ -d "/opt/homebrew/Cellar/vulkan-loader" ]; then
            VULKAN_LIB_PATH="/opt/homebrew/Cellar/vulkan-loader/$(ls -1 /opt/homebrew/Cellar/vulkan-loader | head -1)/lib:${VULKAN_LIB_PATH}"
        fi
        
        # Set environment variables for EGL/Mesa
        # CRITICAL: Include Vulkan library path for Zink
        # Patched EGL library is already in DYLD_LIBRARY_PATH above
        export DYLD_LIBRARY_PATH="${VULKAN_LIB_PATH}:${KOSMICKRISP_LIB}:/opt/homebrew/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
        export LIBGL_DRIVERS_PATH="${KOSMICKRISP_DRI}"
        export MESA_LOADER_DRIVER_OVERRIDE="zink"
        
        # CRITICAL: Do NOT set LIBGL_ALWAYS_SOFTWARE=1 when using Zink!
        # Zink needs a Vulkan device (KosmicKrisp provides Metal-backed Vulkan on macOS)
        # Setting LIBGL_ALWAYS_SOFTWARE=1 forces CPU rendering, which Zink doesn't support
        # Instead, let Zink use the KosmicKrisp Vulkan device (Metal-backed)
        # The Wayland platform backend should handle macOS (no DRM) by using software mode automatically
        
        # Set Vulkan ICD if it exists
        if [ -f "$KOSMICKRISP_ICD" ]; then
            export VK_ICD_FILENAMES="$KOSMICKRISP_ICD"
        fi
        
        # Set EGL platform to Wayland (explicit)
        export EGL_PLATFORM="wayland"
        
        echo -e "${YELLOW}ℹ${NC} EGL environment configured:"
        echo -e "${YELLOW}  ${NC} DYLD_LIBRARY_PATH=${DYLD_LIBRARY_PATH}"
        echo -e "${YELLOW}  ${NC} LIBGL_DRIVERS_PATH=${LIBGL_DRIVERS_PATH}"
        echo -e "${YELLOW}  ${NC} MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE}"
        echo -e "${YELLOW}  ${NC} EGL_PLATFORM=${EGL_PLATFORM}"
        if [ -n "$VK_ICD_FILENAMES" ]; then
            echo -e "${YELLOW}  ${NC} VK_ICD_FILENAMES=${VK_ICD_FILENAMES}"
        fi
        echo -e "${YELLOW}  ${NC} Note: Using Zink with KosmicKrisp Vulkan (Metal-backed) - no LIBGL_ALWAYS_SOFTWARE"
        echo ""
    fi

# Run client interactively (no timeout, runs until SIGTERM)
exec "$CLIENT_PATH" $CLIENT_ARGS

