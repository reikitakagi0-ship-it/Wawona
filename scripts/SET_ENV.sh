#!/bin/bash
# Source this file to set up environment for Wayland clients
# Usage: source SET_ENV.sh [socket-name]
#        or: . SET_ENV.sh wayland-0

SOCKET="${1:-wayland-0}"
export WAYLAND_DISPLAY="$SOCKET"
export XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/wayland-runtime"

echo "Environment set:"
echo "  WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
