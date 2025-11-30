#!/bin/bash
# Script to help test connection to iOS Simulator Wawona Compositor

# Find the log file
LOG_FILE="build/ios-run.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "❌ Log file not found at $LOG_FILE"
    echo "   Run 'make ios-compositor' or 'make ios-compositor-fast' first."
    exit 1
fi

# Extract TCP port from log
# Log line format: ✅ Wayland TCP socket created on port 57707 (127.0.0.1:57707)
PORT=$(grep "✅ Wayland TCP socket created on port" "$LOG_FILE" | tail -1 | grep -oE "[0-9]{4,5}" | head -1)

if [ -z "$PORT" ]; then
    # Try alternate format: ✅ Wayland TCP socket listening on port 57707 (0.0.0.0:57707)
    PORT=$(grep "✅ Wayland TCP socket listening on port" "$LOG_FILE" | tail -1 | grep -oE "[0-9]{4,5}" | head -1)
fi

if [ -z "$PORT" ]; then
    echo "❌ Could not find TCP port in log file."
    echo "   Ensure 'Enable TCP Listener' is enabled in Settings or path fallback is triggered."
    exit 1
fi

echo "✅ Found Wawona TCP port: $PORT"
echo ""
echo "To connect from this Mac:"
echo "  export WAYLAND_DISPLAY=wayland-0"
echo "  export WAYLAND_TCP_PORT=$PORT"
echo "  # Run a client, e.g., waypipe or weston-terminal (if compatible)"
echo ""
echo "To connect from Colima (Linux):"
echo "  # Get Mac host IP visible from Colima (usually 192.168.5.2 or similar)"
echo "  HOST_IP=\$(ifconfig bridge100 | grep inet | awk '{print \$2}')"
echo "  echo \"Connecting to \$HOST_IP:$PORT\""
echo "  waypipe --socket /tmp/wawona-test client ssh -R $PORT:localhost:$PORT user@\$HOST_IP \"WAYLAND_DISPLAY=wayland-0 WAYLAND_TCP_PORT=$PORT weston-terminal\""
echo ""
echo "Note: Direct TCP connection from Linux requires Waypipe or custom client support."

