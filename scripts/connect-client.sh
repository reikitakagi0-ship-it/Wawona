#!/bin/bash
# Helper script to connect Wayland clients to CALayerWayland compositor

# Get socket name from environment or use default
SOCKET="${WAYLAND_DISPLAY:-wayland-0}"

# Set runtime directory (same as compositor uses)
export XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/wayland-runtime"
export WAYLAND_DISPLAY="$SOCKET"

echo "🔌 Connecting to CALayerWayland compositor"
echo "   WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "   XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo ""

# Check if socket exists
if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    echo "⚠️  Warning: Socket not found at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    echo "   Make sure the compositor is running!"
    echo ""
fi

# Run the command passed as arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <command> [args...]"
    echo "Example: $0 ./test_client"
    exit 1
fi

exec "$@"

