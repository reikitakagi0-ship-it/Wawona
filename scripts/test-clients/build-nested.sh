#!/bin/bash
# Build nested compositor test scripts
# Nested compositors test compositor robustness

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NESTED_DIR="$PROJECT_ROOT/test-clients/nested"
INSTALL_DIR="$NESTED_DIR/bin"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔨 Setting Up Nested Compositor Tests${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

mkdir -p "$NESTED_DIR"
mkdir -p "$INSTALL_DIR"

# Create script to run Weston nested
cat > "$INSTALL_DIR/weston-nested" << 'EOFWESTON'
#!/bin/bash
# Run Weston nested inside Wawona compositor

WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
WESTON_BIN=""

# Find Weston binary
if [ -f "$(dirname "$0")/../../weston/build/clients/weston" ]; then
    WESTON_BIN="$(dirname "$0")/../../weston/build/clients/weston"
elif command -v weston &> /dev/null; then
    WESTON_BIN="weston"
else
    echo "Error: Weston not found. Build Weston first with: make test-clients-weston"
    exit 1
fi

echo "Running Weston nested on display: $WAYLAND_DISPLAY"
export WAYLAND_DISPLAY

# Run Weston with wayland backend (nested)
exec "$WESTON_BIN" --backend=wayland --width=800 --height=600 "$@"
EOFWESTON

chmod +x "$INSTALL_DIR/weston-nested"

echo -e "${GREEN}✓${NC} Created weston-nested script"

# Create script to test nested compositor
cat > "$INSTALL_DIR/test-nested" << 'EOFTEST'
#!/bin/bash
# Test nested compositor functionality

WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export WAYLAND_DISPLAY

echo "Testing nested compositor..."
echo "1. Start Wawona compositor"
echo "2. Run: $0 weston-nested"
echo "3. Inside nested Weston, run: weston-simple-shm"
echo ""
echo "Press Enter to continue..."
read

if [ "$1" = "weston-nested" ]; then
    exec "$(dirname "$0")/weston-nested"
else
    echo "Usage: $0 weston-nested"
    exit 1
fi
EOFTEST

chmod +x "$INSTALL_DIR/test-nested"

echo -e "${GREEN}✓${NC} Created test-nested script"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓${NC} Nested compositor scripts created!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}ℹ${NC} Usage:"
echo -e "  1. Start Wawona compositor: make run-compositor"
echo -e "  2. Run nested Weston: ${INSTALL_DIR}/weston-nested"
echo -e "  3. Inside nested Weston, run test clients"
echo ""

