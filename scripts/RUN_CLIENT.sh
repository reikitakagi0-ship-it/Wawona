#!/bin/bash
# Simple script to run the test client with correct environment

# Get socket name (default to wayland-0, but can override). Prefer last socket printed by compositor log.
if [ -z "$WAYLAND_DISPLAY" ] && [ -f "/tmp/compositor-run.log" ]; then
    SOCKET=$(sed -n 's/.*Wayland socket created: \([^ ]*\).*/\1/p' /tmp/compositor-run.log | tail -n1)
    if [ -n "$SOCKET" ]; then
        export WAYLAND_DISPLAY="$SOCKET"
    fi
fi

SOCKET="${WAYLAND_DISPLAY:-wayland-0}"

# Set environment variables
export WAYLAND_DISPLAY="$SOCKET"
export XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/wayland-runtime"

echo "🔌 Connecting to Wayland compositor"
echo "   WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "   XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo ""

# Check if compositor socket exists
if [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    echo "✅ Found compositor socket"
else
    echo "⚠️  Warning: Socket not found at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    echo "   Make sure the compositor is running!"
    echo "   Check compositor output for the correct socket name."
    echo ""
    # Try to auto-detect an available socket
    for s in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [ -S "$s" ]; then
            export WAYLAND_DISPLAY="$(basename "$s")"
            echo "   Using detected socket: $WAYLAND_DISPLAY"
            break
        fi
    done
fi

# Run the test client
echo "🚀 Starting test client..."
echo ""
./test_client










