# Client Setup Guide

## Environment Variables

When connecting Wayland clients to the compositor, you need to set:

### Required

1. **WAYLAND_DISPLAY** - The socket name (e.g., `wayland-0`)
   ```bash
   export WAYLAND_DISPLAY=wayland-0
   ```

2. **XDG_RUNTIME_DIR** - Runtime directory (auto-set by compositor)
   ```bash
   # Usually auto-set, but if needed:
   export XDG_RUNTIME_DIR=/tmp/wayland-runtime
   ```

### Quick Setup Script

Create a helper script `connect-client.sh`:

```bash
#!/bin/bash
# Connect to Wawona compositor

# Get socket name from compositor output or use default
SOCKET="${WAYLAND_DISPLAY:-wayland-0}"

# Set runtime directory (same as compositor uses)
export XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/wayland-runtime"
export WAYLAND_DISPLAY="$SOCKET"

echo "Connecting to Wayland display: $WAYLAND_DISPLAY"
echo "Runtime directory: $XDG_RUNTIME_DIR"

# Run the command passed as arguments
exec "$@"
```

Usage:
```bash
chmod +x connect-client.sh
./connect-client.sh ./test_client
```

## Finding the Socket Name

The compositor prints the socket name when it starts:
```
✅ Wayland socket created: wayland-0
   Clients can connect with: export WAYLAND_DISPLAY=wayland-0
```

Use that exact socket name.

## Troubleshooting

### "XDG_RUNTIME_DIR is invalid or not set"
- Make sure `XDG_RUNTIME_DIR` is set
- Check that the directory exists and is writable
- The compositor creates it automatically, so use the same path

### "Failed to connect to Wayland display"
- Verify compositor is running
- Check `WAYLAND_DISPLAY` matches the socket name
- Ensure `XDG_RUNTIME_DIR` is set correctly
- Check socket exists: `ls $XDG_RUNTIME_DIR/wayland-*`

### Socket not found
- Make sure compositor started successfully
- Check compositor logs for socket creation
- Verify runtime directory exists

## Test Client

The included `test_client` automatically sets `XDG_RUNTIME_DIR` if not set, so you only need:

```bash
export WAYLAND_DISPLAY=wayland-0
./test_client
```

