#!/bin/bash
# Common variables and functions for colima-client scripts

# Get script directory (where this common.sh is located) - MUST be first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Container configuration
CONTAINER_IMAGE="nixos/nix:latest"
CONTAINER_NAME="weston-container"

# Wayland runtime configuration
# If IOS_SIMULATOR_MODE is explicitly set to 1, force iOS mode
# Otherwise, auto-detect based on socket availability
if [ "${IOS_SIMULATOR_MODE:-0}" = "1" ]; then
    # Force iOS Simulator mode - try to find socket
    IOS_SOCKET_INFO=""
    if command -v xcrun >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/../ios-simulator-socket.sh" ]; then
        # Capture both stdout and stderr to show detailed error messages
        IOS_SOCKET_INFO=$("$SCRIPT_DIR/../ios-simulator-socket.sh" 2>&1)
        SOCKET_EXIT_CODE=$?
        if [ $SOCKET_EXIT_CODE -ne 0 ]; then
            # Show the error message from the socket script
            # Print to both stderr and stdout so Make will show it
            echo "" >&2
            echo "$IOS_SOCKET_INFO" >&2
            echo "" >&2
            # Also print to stdout for Make visibility
            echo ""
            echo "$IOS_SOCKET_INFO"
            echo ""
            # Return error code 1 to signal failure
            return 1
        fi
    fi
    
    if [ -n "$IOS_SOCKET_INFO" ]; then
        # Use iOS Simulator socket
        IOS_SOCKET=$(echo "$IOS_SOCKET_INFO" | cut -d'|' -f1)
        IOS_RUNTIME_DIR=$(echo "$IOS_SOCKET_INFO" | cut -d'|' -f2)
        XDG_RUNTIME_DIR="$IOS_RUNTIME_DIR"
        WAYLAND_DISPLAY=$(basename "$IOS_SOCKET")
        SOCKET_PATH="$IOS_SOCKET"
        export IOS_SIMULATOR_MODE=1
    else
        echo "Error: IOS_SIMULATOR_MODE=1 but iOS Simulator socket not found" >&2
        echo "Make sure Wawona is running in iOS Simulator: make ios-compositor" >&2
        return 1
    fi
else
    # Auto-detect: Check for iOS Simulator socket first
    IOS_SOCKET_INFO=""
    if command -v xcrun >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/../ios-simulator-socket.sh" ]; then
        IOS_SOCKET_INFO=$("$SCRIPT_DIR/../ios-simulator-socket.sh" 2>/dev/null || echo "")
    fi
    
    if [ -n "$IOS_SOCKET_INFO" ]; then
        # Use iOS Simulator socket
        IOS_SOCKET=$(echo "$IOS_SOCKET_INFO" | cut -d'|' -f1)
        IOS_RUNTIME_DIR=$(echo "$IOS_SOCKET_INFO" | cut -d'|' -f2)
        XDG_RUNTIME_DIR="$IOS_RUNTIME_DIR"
        WAYLAND_DISPLAY=$(basename "$IOS_SOCKET")
        SOCKET_PATH="$IOS_SOCKET"
        export IOS_SIMULATOR_MODE=1
    else
        # Use macOS socket (default)
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}"
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
        SOCKET_PATH="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
        export IOS_SIMULATOR_MODE=0
    fi
fi

# Colima-compatible paths
COCOMA_XDG_RUNTIME_DIR="${HOME}/.wayland-runtime"

# Waypipe configuration
WAYPIPE_SOCKET="${HOME}/.wayland-runtime/waypipe.sock"
WAYPIPE_CLIENT_PID=""
