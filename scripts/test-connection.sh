#!/bin/bash
# Quick test script - starts compositor and client

echo "🎯 CALayerWayland Quick Test"
echo ""

# Start compositor in background
echo "Starting compositor..."
./build/Wawona > /tmp/compositor.log 2>&1 &
COMPOSITOR_PID=$!

# Wait for socket to be created
sleep 2

# Get socket name from log
SOCKET=$(grep "socket created" /tmp/compositor.log | grep -o "wayland-[0-9]*" | head -1)

if [ -z "$SOCKET" ]; then
    echo "❌ Failed to get socket name"
    kill $COMPOSITOR_PID 2>/dev/null
    exit 1
fi

echo "✓ Compositor running (PID: $COMPOSITOR_PID)"
echo "✓ Socket: $SOCKET"
echo ""

# Set environment
export WAYLAND_DISPLAY="$SOCKET"
export XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/wayland-runtime"

echo "Running test client..."
echo "Press Ctrl+C to stop"
echo ""

# Run client
./test_client

# Cleanup
kill $COMPOSITOR_PID 2>/dev/null
