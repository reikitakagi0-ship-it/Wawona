#!/bin/bash
# Helper script to find iOS Simulator Wayland socket path
# Used by colima-client to connect to iOS Simulator Wawona

set -e

# Find booted iOS Simulator device
# If IOS_SIMULATOR_MODE is set, prefer "DebugPhone" device
if [ "${IOS_SIMULATOR_MODE:-0}" = "1" ]; then
    DEVICE_ID=$(xcrun simctl list devices booted | grep "DebugPhone" | grep -oE '[0-9A-F-]{36}' || echo "")
    if [ -z "$DEVICE_ID" ]; then
        echo "No booted 'DebugPhone' iOS Simulator device found" >&2
        echo "Make sure DebugPhone is booted: xcrun simctl boot <device-id>" >&2
        exit 1
    fi
else
    DEVICE_ID=$(xcrun simctl list devices booted | grep -E "iPhone|iPad" | head -1 | grep -oE '[0-9A-F-]{36}' || echo "")
    if [ -z "$DEVICE_ID" ]; then
        echo "No booted iOS Simulator device found" >&2
        exit 1
    fi
fi

# Get app data container
DATA_CONTAINER=$(xcrun simctl get_app_container "$DEVICE_ID" com.aspauldingcode.Wawona data 2>/dev/null || echo "")

if [ -z "$DATA_CONTAINER" ]; then
    echo "Wawona app not installed or device not booted" >&2
    exit 1
fi

# Wayland socket is in /tmp/wawona-ios on host filesystem (shortest path to avoid Unix socket 108-byte limit)
# iOS Simulator can access host /tmp directory
# Socket name is "w0" instead of "wayland-0" for shorter path
RUNTIME_DIR="/tmp/wawona-ios"

# Note: Directory might not exist yet if Wawona hasn't been launched
# The retry loop below will wait for it to be created (up to 10 seconds)
# We don't check if Wawona is running here because:
# 1. Process checking in simulators is unreliable across different macOS versions
# 2. The socket existence check below will handle whether it's actually running

# Find the Wayland socket (w0 or wayland-0)
# Wait for socket to be created if Wawona just started (up to 10 seconds)
SOCKET=""
MAX_ATTEMPTS=20  # 20 attempts * 0.5s = 10 seconds max wait
for i in $(seq 1 $MAX_ATTEMPTS); do
    # Ensure directory exists (Wawona might create it on first launch)
    if [ ! -d "$RUNTIME_DIR" ]; then
        if [ $i -lt $MAX_ATTEMPTS ]; then
            sleep 0.5
            continue
        else
            echo "Wayland runtime directory does not exist: $RUNTIME_DIR" >&2
            echo "Make sure Wawona has been launched at least once in the simulator" >&2
            exit 1
        fi
    fi
    
    # Check if directory is writable (socket creation might be failing)
    if [ $i -eq 1 ] && [ ! -w "$RUNTIME_DIR" ]; then
        echo "Wayland runtime directory is not writable: $RUNTIME_DIR" >&2
        echo "Directory permissions: $(stat -f "%Sp" "$RUNTIME_DIR" 2>/dev/null || echo "unknown")" >&2
        exit 1
    fi
    
    # Try short name first (w0), then fall back to wayland-*
    SOCKET=$(find "$RUNTIME_DIR" -type s -name "w0" 2>/dev/null | head -1)
    if [ -z "$SOCKET" ]; then
        SOCKET=$(find "$RUNTIME_DIR" -type s -name "wayland-*" 2>/dev/null | head -1)
    fi
    if [ -n "$SOCKET" ]; then
        break
    fi
    
    # Show progress for first few attempts
    if [ $i -le 3 ]; then
        echo "Waiting for Wayland socket... (attempt $i/$MAX_ATTEMPTS)" >&2
    fi
    sleep 0.5
done

if [ -z "$SOCKET" ]; then
    echo "Wayland socket not found in $RUNTIME_DIR" >&2
    echo "Wawona is running but hasn't created the socket yet" >&2
    echo "" >&2
    echo "Debugging information:" >&2
    echo "  Runtime directory: $RUNTIME_DIR" >&2
    echo "  Directory exists: $([ -d "$RUNTIME_DIR" ] && echo "yes" || echo "no")" >&2
    echo "  Directory writable: $([ -w "$RUNTIME_DIR" ] && echo "yes" || echo "no")" >&2
    echo "  Directory contents: $(ls -la "$RUNTIME_DIR" 2>&1 | head -5)" >&2
    echo "" >&2
    echo "This may indicate:" >&2
    echo "  1. Wawona failed to create the socket during initialization" >&2
    echo "  2. The socket was created but then removed" >&2
    echo "  3. There's a permissions issue preventing socket creation" >&2
    echo "" >&2
    echo "Check Wawona logs:" >&2
    echo "  xcrun simctl spawn $DEVICE_ID log stream --predicate 'processImagePath contains \"Wawona\"' --level debug" >&2
    echo "" >&2
    echo "Try restarting Wawona:" >&2
    echo "  make ios-compositor" >&2
    exit 1
fi

# Output socket path and XDG_RUNTIME_DIR
echo "$SOCKET|$RUNTIME_DIR"

