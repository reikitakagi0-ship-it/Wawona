#!/bin/bash
# Master script to build all Wayland test clients

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔨 Building All Wayland Test Clients${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create test-clients directory structure
mkdir -p "$PROJECT_ROOT/test-clients/bin"
mkdir -p "$PROJECT_ROOT/test-clients/weston/bin"
mkdir -p "$PROJECT_ROOT/test-clients/minimal/bin"
mkdir -p "$PROJECT_ROOT/test-clients/debug/bin"
mkdir -p "$PROJECT_ROOT/test-clients/nested/bin"

# Build minimal clients first (fastest, least dependencies)
echo -e "${YELLOW}[1/4]${NC} Building minimal test clients..."
"$SCRIPT_DIR/build-minimal.sh"
echo ""

# Build debugging tools
echo -e "${YELLOW}[2/4]${NC} Building debugging tools..."
"$SCRIPT_DIR/build-debug-tools.sh"
echo ""

# Build Weston clients (may take longer)
echo -e "${YELLOW}[3/4]${NC} Building Weston demo clients..."
echo -e "${YELLOW}⚠${NC}  This may take several minutes..."
"$SCRIPT_DIR/build-weston.sh"
echo ""

# Build nested compositor scripts
echo -e "${YELLOW}[4/4]${NC} Setting up nested compositor tests..."
"$SCRIPT_DIR/build-nested.sh"
echo ""

# Create symlinks in main bin directory
echo -e "${YELLOW}ℹ${NC} Creating symlinks..."
for dir in "$PROJECT_ROOT/test-clients"/{minimal,debug,weston}/bin/*; do
    if [ -f "$dir" ] && [ -x "$dir" ]; then
        ln -sf "$dir" "$PROJECT_ROOT/test-clients/bin/$(basename "$dir")"
    fi
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓${NC} All test clients built!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}ℹ${NC} Test clients installed to: $PROJECT_ROOT/test-clients/bin"
echo -e "${YELLOW}ℹ${NC} Run tests with: export WAYLAND_DISPLAY=wayland-0 && $PROJECT_ROOT/test-clients/bin/<client-name>"
echo ""

